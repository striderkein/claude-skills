#!/usr/bin/env python3
"""組み上がった投稿文を Slack へ流す。

トリアージ（LLM）と投稿（決定的処理）を分離するための後段。スキルは文面を
`out/<日付>/post.md` に書くところまでを担当し、実際の送信はこのスクリプトが行う。
こうしておくと、ローカルでも GitHub Actions でも同じ経路で投稿でき、
文面だけ差し替えて再送する・投稿だけ再実行する、といった運用ができる。

  python3 post_slack.py out/2026-07-31/post.md            # 全チャンネルへ投稿
  python3 post_slack.py out/2026-07-31/post.md --dry-run  # 送信せず宛先と本文を表示

  python3 slack_post.py --whoami                          # トークンの持ち主を表示

認証は Slack Bot Token（`SLACK_BOT_TOKEN`、`xoxb-` で始まる）。
必要な Bot Token Scope は `chat:write` と、未参加チャンネルへ投稿する場合は `chat:write.public`。

投稿先は `--channel` で直接指定するか、`config.json` の `slack_channels` に書く
（環境変数 `SLACK_POST_CONFIG` → カレントディレクトリ → このスクリプトの隣、の順で探す）。

`chat.postMessage` は標準 Markdown を解釈しないため、送信直前に mrkdwn へ変換している。
本文は人が読める標準 Markdown のまま保存できる。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def config_path() -> str:
    """投稿先の設定ファイルを探す。

    プロジェクトごとに置き場所が違うので、環境変数 → カレント → スクリプトの隣、の順に見る。
    --channel で直接指定する場合は設定ファイル自体が要らない。
    """
    env = os.environ.get("SLACK_POST_CONFIG")
    if env:
        return env
    for cand in (os.path.join(os.getcwd(), "config.json"), os.path.join(BASE_DIR, "config.json")):
        if os.path.exists(cand):
            return cand
    return os.path.join(os.getcwd(), "config.json")
SLACK_API = "https://slack.com/api/chat.postMessage"


def to_mrkdwn(text: str) -> str:
    """標準 Markdown を Slack の mrkdwn へ変換する。

    chat.postMessage は標準 Markdown を解釈しない。`**太字**` はアスタリスクごと
    そのまま表示されてしまう。post.md は人が読める標準 Markdown で書き、
    送信直前にここで変換する。
    """
    out_lines = []
    in_code = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_code = not in_code
            out_lines.append(line)
            continue
        if in_code:
            out_lines.append(line)
            continue
        # 見出し `## タイトル` → 太字
        line = re.sub(r"^\s{0,3}#{1,6}\s+(.*?)\s*$", r"*\1*", line)
        # 箇条書き `- ` → `• `（Slack は - をそのまま出すので見た目を揃える）
        line = re.sub(r"^(\s*)-\s+", r"\1• ", line)
        # インラインコードの中は変換しない（`**` を文字として見せたい場合がある）
        parts = re.split(r"(`[^`]*`)", line)
        for i, part in enumerate(parts):
            if part.startswith("`"):
                continue
            # 太字 `**x**` → `*x*`
            part = re.sub(r"\*\*(.+?)\*\*", r"*\1*", part)
            # リンク `[表示](url)` → `<url|表示>`
            part = re.sub(r"\[([^\]]+)\]\((https?://[^\s)]+)\)", r"<\2|\1>", part)
            parts[i] = part
        out_lines.append("".join(parts))
    return "\n".join(out_lines)


def post(token: str, channel: str, text: str) -> dict:
    payload = json.dumps(
        {
            "channel": channel,
            "text": text,
            # Slack 側のリンク展開で本文が埋もれるのを防ぐ（URL は本文中に明示している）
            "unfurl_links": False,
            "unfurl_media": False,
        }
    ).encode()
    req = urllib.request.Request(
        SLACK_API,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("post_file", nargs="?", help="投稿する Markdown ファイル（out/<日付>/post.md）")
    ap.add_argument("--whoami", action="store_true",
                    help="トークンの持ち主（App ID・bot ユーザー・ワークスペース）を表示する")
    ap.add_argument("--dry-run", action="store_true", help="送信せず宛先と本文を表示する")
    ap.add_argument("--channel", action="append", help="config.json ではなく指定チャンネルへ送る（複数可）")
    args = ap.parse_args()

    if args.whoami:
        token = os.environ.get("SLACK_BOT_TOKEN", "").strip()
        if not token:
            print("SLACK_BOT_TOKEN が未設定", file=sys.stderr)
            return 1
        req = urllib.request.Request(
            "https://slack.com/api/auth.test",
            data=b"",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            info = json.loads(resp.read().decode())
        # 秘密情報は含まれない（App ID・bot ユーザー ID・ワークスペース名だけ）
        for k in ("ok", "app_id", "bot_id", "user_id", "user", "team", "team_id", "error"):
            if k in info:
                print(f"{k:<10} {info[k]}")
        return 0 if info.get("ok") else 1

    if not args.post_file:
        print("投稿ファイルを指定する（--whoami 以外では必須）", file=sys.stderr)
        return 1

    if not os.path.exists(args.post_file):
        print(f"投稿ファイルがない: {args.post_file}", file=sys.stderr)
        return 1

    with open(args.post_file, encoding="utf-8") as f:
        text = to_mrkdwn(f.read().strip())

    if not text:
        print("投稿ファイルが空。何もしない", file=sys.stderr)
        return 0

    if args.channel:
        channels = [{"id": c, "name": c} for c in args.channel]
    else:
        path = config_path()
        if not os.path.exists(path):
            print(f"投稿先の設定が無い: {path}\n"
                  "config.json に slack_channels を書くか、--channel でチャンネル ID を指定する",
                  file=sys.stderr)
            return 1
        with open(path, encoding="utf-8") as f:
            channels = json.load(f)["slack_channels"]

    if args.dry_run:
        print(f"# dry-run: {len(channels)} チャンネルへ投稿予定")
        for ch in channels:
            print(f"#   - {ch['id']} ({ch.get('name', '')})")
        print(f"# 本文 {len(text)} 文字\n")
        print(text)
        return 0

    token = os.environ.get("SLACK_BOT_TOKEN", "").strip()
    if not token:
        print("SLACK_BOT_TOKEN が未設定。投稿できない", file=sys.stderr)
        return 1

    failed = 0
    for ch in channels:
        try:
            result = post(token, ch["id"], text)
        except urllib.error.URLError as e:
            print(f"FAIL  {ch['id']} ({ch.get('name','')}): {e}", file=sys.stderr)
            failed += 1
            continue
        if result.get("ok"):
            print(f"OK    {ch['id']} ({ch.get('name','')}) ts={result.get('ts')}")
        else:
            # not_in_channel はチャンネル未参加。chat:write.public を付けるか bot を招待する
            print(f"FAIL  {ch['id']} ({ch.get('name','')}): {result.get('error')}", file=sys.stderr)
            failed += 1

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
