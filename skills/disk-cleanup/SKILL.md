---
name: disk-cleanup
description: macOS でディスク空き容量を最大化する。Docker prune (volumes 除外で DB データ保持) + 安全キャッシュ削除 + node_modules 一括削除を段階的に実行。「容量足りない」「ストレージ空けて」「ディスク掃除」「空き容量増やして」「disk cleanup」「容量解放」「容量がやばい」等で発動。開発中に積もった不要キャッシュ・ビルドアーティファクトを掃除して GB 単位で空ける時に使う。
---

# Disk Cleanup

開発で積もったキャッシュ・ビルドアーティファクト・Docker レイヤを段階的に掃除して空き容量を最大化する。

破壊的操作を含むため、必ず**段階を分けて確認しながら**実行する。一気に `rm -rf` 連打する skill ではない。

## Usage

- `/disk-cleanup` — 対話モード (各段階でユーザ確認)
- `/disk-cleanup auto` — 安全段階 (Stage 1-3) のみ自動実行、node_modules は確認
- `/disk-cleanup max` — node_modules 含め全段階実行 (最大解放)

## Execution Steps

### Step 1: ベースライン計測

開始時の空き容量と大物候補を並列で計測する。

```bash
df -h /
docker system df 2>/dev/null
du -sh ~/Library/Caches ~/.cache ~/Library/Application\ Support 2>/dev/null
```

ユーザに**開始空き容量**を提示する。

### Step 2: 大物候補リストアップ

実際に何がどれだけ食っているか可視化する。`du` は遅いので並列に走らせる。

```bash
du -sh ~/Library/Caches/* 2>/dev/null | sort -hr | head -10
du -sh ~/.cache/* 2>/dev/null | sort -hr | head -10
du -sh ~/Library/Application\ Support/* 2>/dev/null | sort -hr | head -10
docker system df -v 2>/dev/null | sed -n '/Local Volumes/,$p'
```

候補を表で提示する:

| Category | Path | Size | 削除可否 |
|---|---|---|---|
| Docker images + build cache | docker prune | (reclaimable) | 安全 (volumes 除外) |
| Yarn cache | `~/Library/Caches/Yarn` | ? | プロジェクトが pnpm/npm 移行済なら安全。Yarn 現役なら保持 |
| chrome-devtools-mcp | `~/.cache/chrome-devtools-mcp` | ? | 安全 (再 DL) |
| uv cache | `~/.cache/uv` | ? | 安全 (再 DL) |
| puppeteer cache | `~/.cache/puppeteer` | ? | 安全 (再 DL) |
| ShipIt | `~/Library/Caches/com.todesktop.*.ShipIt` | ? | 安全 (アプリ更新済) |
| node-gyp | `~/Library/Caches/node-gyp` | ? | 安全 |
| npm _cacache | `~/.npm/_cacache` | ? | 安全 |
| brew old versions | `brew cleanup` | ? | 安全 |
| **保持必須** | | | |
| ms-playwright | `~/Library/Caches/ms-playwright` | ? | **NG** (Playwright 使用プロジェクトあれば再 DL 待ち) |
| pnpm store | `~/Library/Caches/pnpm` | ? | **NG** (現役の pnpm hardlink 元) |
| Docker volumes | `docker volume ls` で確認 | ? | **NG** (DB データ等の永続層) |
| Chrome user data | `~/Library/Application Support/Google/Chrome` | ? | 要確認 (BM・拡張喪失) |

### Step 3: Docker prune

**`--volumes` フラグは絶対に付けない**。DB データ等の永続層が消える。事前に `docker volume ls` で内容把握しておく。

```bash
docker system prune -a -f
```

解放量を `Total reclaimed space:` 行で確認・記録する。

### Step 4: 安全キャッシュ一括削除

並列で削除可能。ユーザ確認後に実行:

```bash
rm -rf ~/Library/Caches/Yarn \
       ~/.cache/chrome-devtools-mcp \
       ~/.cache/uv \
       ~/.cache/puppeteer \
       ~/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt \
       ~/Library/Caches/node-gyp \
       ~/.npm/_cacache
brew cleanup --prune=all
```

**削除してはいけない**:
- `~/Library/Caches/ms-playwright` — Playwright 使用プロジェクトで再 DL 待ち発生
- `~/Library/Caches/pnpm` — pnpm store、hardlink 元、現役
- `~/Library/Caches/Google` (Chrome キャッシュ) を消すかは要確認 — セッション・履歴は別パスだが念のためユーザに聞く

### Step 5: node_modules 一括削除 (オプション、最大解放)

最大級の解放源になりうる (実例: 73 dir / 49GB)。ただし**全プロジェクトで再 install 必要**になるため必ず明示確認。

スキャン対象は `~/dev` をデフォルトとし、ユーザが別パスを指定したらそちらを使う (`~/projects`, `~/src` 等)。`/` や `~` ルート全体は禁止。

```bash
# Step 5a: 計測 (SCAN_ROOT はユーザ指定 or ~/dev デフォルト)
SCAN_ROOT="${SCAN_ROOT:-$HOME/dev}"
find "$SCAN_ROOT" -type d -name node_modules -prune 2>/dev/null > /tmp/nm-list.txt
wc -l /tmp/nm-list.txt
xargs du -sm < /tmp/nm-list.txt 2>/dev/null | awk '{s+=$1} END {print s " MB total"}'
```

**ユーザに件数 + 合計サイズ + スキャン対象パスを提示し、明示 yes を得てから**:

```bash
xargs rm -rf < /tmp/nm-list.txt
# pnpm の hardlink 構造で 1 pass 目に "Directory not empty" が残ることがあるので 2 pass:
find "$SCAN_ROOT" -type d -name node_modules -prune 2>/dev/null | xargs rm -rf
rm /tmp/nm-list.txt
```

注意:
- スキャン対象パスを必ずユーザに提示してから実行。`/` や `~` 全体は禁止 (遅い + 危険)
- `-prune` 必須。node_modules 内部の入れ子 node_modules まで降りると find が遅くなる + 重複削除でエラー

### Step 6: サマリ出力

`df -h /` を再実行して開始時との差分を出す:

```
## Cleanup Complete

開始: 8.5GB free → 終了: 71GB free (+62.5GB)

- Docker prune: 2.0GB
- 安全キャッシュ (Yarn/uv/puppeteer/chrome-devtools-mcp 等): 11.5GB
- brew cleanup: 0.4GB
- node_modules 73 dir: 49GB

次回再開時の復元コスト:
- 該当 worktree で `pnpm install`
- puppeteer / chrome-devtools-mcp は次回 MCP 起動時に自動 DL
```

## Safety Rules (絶対遵守)

1. **`docker system prune` に `--volumes` を付けない** — DB データ等の永続層が消失
2. **node_modules 削除はユーザ指定 (default `~/dev`) 配下のみ** — `/` 全体や `~` ルートからの find は禁止
3. **ms-playwright cache は触らない** — Playwright 使用プロジェクトで再 DL 待ち発生
4. **Chrome user data (Application Support/Google/Chrome) はデフォルト保持** — 削除する場合は事前にユーザ確認 (BM・拡張・セッション喪失)
5. **削除前に必ず `du -sh` で実サイズを確認** — 候補リストの数字は古い可能性
6. **2 pass 戦略** — pnpm hardlink 構造は 1 回の rm で消えないことがある、`find | wc -l` で 0 になるまで繰り返す

## Why each cache is safe to remove

- **Yarn**: 対象プロジェクトが pnpm/npm に移行済なら参照されない (Yarn 現役プロジェクト混在時は保持判断)
- **chrome-devtools-mcp / puppeteer**: 各 MCP / Playwright が起動時に必要分を自動 DL
- **uv**: Python パッケージマネージャのキャッシュ、再実行時に再取得
- **ShipIt**: アプリ updater (Squirrel) の古いインストーラ残骸
- **node-gyp**: ネイティブビルド時に再取得
- **npm `_cacache`**: pnpm 移行プロジェクトでは不要、必要時は再 DL
- **brew cleanup**: 古いバージョンの formula 残骸

## What NOT to do

- `docker system prune -a -f --volumes` — DB 飛ぶ
- `find / -name node_modules` — 走査時間爆発 + 権限エラー
- `rm -rf ~/Library/Caches/*` — ms-playwright 含む保持必須も消える
- アクティビティモニタの「ディスク」タブの数値を**ストレージ使用量と勘違い**しない (あれは累積 I/O)
