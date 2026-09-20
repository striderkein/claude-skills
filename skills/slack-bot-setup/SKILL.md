---
name: slack-bot-setup
description: 通知用の Slack App（bot）をマニフェストから作り、投稿まで通す手順。マニフェスト検証で弾かれる項目、ハンドルからハイフンが落ちる仕様、表示名の日本語対応、Bot Token の取得と GitHub Secrets への登録、chat.postMessage が標準 Markdown を解釈しない件、アイコンの作り方までを網羅する。「Slack App 作りたい」「bot から通知したい」「Slack に自動投稿」「Slack Bot Token」「incoming webhook の代わり」「マニフェストが弾かれる」等で発動。CI やスクリプトから一方向で通知したい場合に使う（対話応答が要る場合は常駐が必要になるため対象外）。
argument-hint: "[アプリ名] [投稿先チャンネル]"
---

# Slack 通知 bot のセットアップ

CI やスクリプトから Slack へ投稿する bot を作る手順。**一方向の通知専用**を前提にする
（メンションに応答させるにはイベント購読と常駐プロセスが要る。それは別物として扱う）。

Incoming Webhook ではなく Bot Token を使う。Webhook はチャンネルごとに URL が必要で
増やすたびに発行し直しになるが、Bot Token なら1本で複数チャンネルに投げられる。

所要 20〜30分。ワークスペースの設定によっては App のインストールに管理者承認が要る。

## Step 1: マニフェストを用意する

`assets/manifest.json` と `assets/manifest.yml` が雛形（中身は同じ）。名前と説明を置き換える。

```json
{
  "display_information": {
    "name": "アプリ名",
    "description": "1行の説明",
    "background_color": "#2b5797",
    "long_description": "何を通知し、どこから実行され、何を扱うのかを書く（短いと弾かれる）"
  },
  "features": { "bot_user": { "display_name": "ascii_name", "always_online": true } },
  "oauth_config": { "scopes": { "bot": ["chat:write", "chat:write.public"] } },
  "settings": { "org_deploy_enabled": false, "socket_mode_enabled": false, "token_rotation_enabled": false }
}
```

**検証で弾かれる典型**（実際に踏んだもの）:

| 症状 | 原因 |
|---|---|
| `Invalid manifest` | `settings` に仕様外のキーがある。置けるのは `org_deploy_enabled` / `socket_mode_enabled` / `token_rotation_enabled` / `event_subscriptions` / `interactivity` / `allowed_ip_address_ranges` 程度。`is_hosted` のような存在しないキーを書くと落ちる |
| 貼り付け内容が不正と言われる | **貼り付け欄の既定は JSON タブ**。YAML を貼るならタブを切り替える |
| コメント行でエラー | JSON はコメント不可。YAML でも余計な行があると弾かれることがある。手順の説明はマニフェストの外に書く |
| `long_description` が短い | 短いと弾かれることがある。実測では 184 文字で通過している。機能・実行元・扱う情報の3点を書けば足りる |
| `bot_user.display_name` でエラー | **全角日本語は通らない**。ASCII で書く。日本語表示にしたい場合は Step 4 で UI から設定する |
| YAML の値が不正 | 日本語の値をクオートで囲む。ブロックスカラー（`>-`）も避けて1行の文字列にする |

## Step 2: App を作る

1. https://api.slack.com/apps → **Create New App** → **From an app manifest**
2. ワークスペースを選ぶ
3. マニフェストを貼り付けて **Next** → **Create**
4. Review 画面で確認して **Create and Install**
   - "What it can do in Slack (2)" = `chat:write` と `chat:write.public`
   - "What it can respond to (0)" = イベント購読なし。一方向 App なので 0 が正しい
5. OAuth 認可画面で **許可する**

作成完了画面に Slack CLI の手順が出るが**無視してよい**。あれは Bolt でアプリを常駐開発する人向けで、
HTTP で `chat.postMessage` を叩くだけなら CLI もローカルサーバも要らない。

**この画面に出る App ID（`A0...`）を控えておく。** 後で「どのアプリが稼働中か」を確かめるときに要る。
作成に失敗した試行が残っていると、同名の App が複数並んで判別できなくなる。

## Step 3: Bot Token を取得して保管する

左メニュー **OAuth & Permissions** → **Bot User OAuth Token**（`xoxb-` で始まる）。

同じ画面の **Scopes → Bot Token Scopes** に `chat:write` と `chat:write.public` の2つだけが
並んでいることを確認する。

**トークンは会話やチャット履歴に貼らせない。** クリップボード経由で直接渡す。

```bash
pbpaste | gh secret set SLACK_BOT_TOKEN --repo <owner>/<repo>
```

ローカルで試すときは環境変数で渡す（シェル履歴に残る点は留意する）:

```bash
export SLACK_BOT_TOKEN=xoxb-...
```

## Step 4: 表示名とハンドルを整える

**App Home → Your App's Presence → Edit** に2つの欄がある。役割が違う。

| 欄 | 役割 | 制約 |
|---|---|---|
| Display Name (Bot Name) | **投稿時の送信者名** | 80文字未満。アポストロフィとピリオド以外の約物は不可。**日本語が使える**（マニフェスト検証より緩い） |
| Default username | **`@` メンションのハンドル** | 小文字のみ・21文字以内・英数字とピリオド・ハイフン・アンダースコア |

**ハイフンは Slack が落とす。** `logi-law-watch` は `@logilawwatch` になって読みにくい。
**アンダースコアは残る**ので `logi_law_watch` にすると `@logi_law_watch` になる。

推奨の組み合わせ:

```
Display Name (Bot Name): 物流法制ウォッチ      ← 日本語で可読性を優先
Default username:        logi_law_watch       ← ASCII + アンダースコア
```

App を作り直す必要はない。ここで変更すれば即反映される。

なお**既に発行済みの bot ユーザー名は作成時のものが残る**ことがある（`users.info` では
古いハンドルのまま見えることがある）。メンションは Slack が補完するので実害はない。

## Step 5: チャンネルに招待する

```
/invite @<Default username>
```

`chat:write.public` があれば未参加の public チャンネルにも投げられるが、
参加させておく方がメンバーから見て何が投稿しているか分かりやすい。

## Step 6: 投稿する

`scripts/slack_post.py` が使える。Markdown ファイルを読んで全チャンネルに同じ本文を投げる。

```bash
python3 slack_post.py post.md --dry-run                 # 宛先と変換後の本文を確認
python3 slack_post.py post.md --channel C0XXXX          # チャンネル直指定
SLACK_BOT_TOKEN=xoxb-... python3 slack_post.py post.md  # 実投稿
python3 slack_post.py --whoami                          # トークンの持ち主を表示
```

既定の宛先は同じディレクトリの `config.json` の `slack_channels` から読む。

```json
{ "slack_channels": [ { "id": "C0XXXXXXX", "name": "#通知先" } ] }
```

**`chat.postMessage` は標準 Markdown を解釈しない。** `**太字**` はアスタリスクごと表示される。
Slack の mrkdwn は `*太字*`、リンクは `<url|表示>`。`slack_post.py` は送信直前に変換するので、
本文は標準 Markdown で書いてよい（人が読める形のまま保存できる）。

投稿本文にリンクを並べる場合は `unfurl_links: false` を付ける。プレビュー展開で本文が埋もれる。

## つまずいたときの対処

| 症状 | 対処 |
|---|---|
| `not_in_channel` | bot がチャンネル未参加。`/invite` するか `chat:write.public` を付ける |
| `missing_scope` | scope を足したら**再インストールしないと反映されない**。App 設定に警告バナーが出る |
| `You've changed the permission scopes...` の警告 | 表示名の変更だけでも出ることがある。**再インストールしてからトークンを取り直す**。再インストールでトークンが変わる場合がある |
| `invalid_auth` | トークンが失効しているか、App が削除・アンインストールされている |
| 同名の App が複数並ぶ | 作成に失敗した試行の残骸。Step 7 で稼働中のものを特定してから消す |

## Step 7: どの App が稼働中かを特定する

同名の App が複数ある状態で片方を消すと、稼働中のトークンを失う。消す前に確かめる。

```bash
python3 slack_post.py --whoami
```

`auth.test` は **`app_id` を返さない**（`bot_id` / `user_id` / `user` / `team` のみ）。
そのため App ID の特定は次の材料を突き合わせる。

1. 作成完了画面に出ていた App ID（Step 2 で控えたもの）
2. `bot_id` と App ID の**プレフィックスが同時刻帯で一致する**（`A0BLT...` と `B0BLT...`）
3. アイコンや表示名を設定した方が稼働中のもの
4. 決定的な確認: 各 App の **Install App** ページを開く。「Install to Workspace」ボタンが出ている
   （＝未インストール、トークン未発行）なら消して安全。**Bot User OAuth Token が表示されていたら消さない**

使っていない App を残しても実害はない（未インストールなら権限も持たない）。
迷うなら消さずに放置してよい。削除は取り消せない。

## アイコンを作る

**Basic Information → Display Information → App icon** からアップロードする。
Slack の要件は正方形・512px 以上 2000px 以下・5MB 未満。

`assets/icon-template.svg` を書き換えて、macOS 標準の `qlmanage` で PNG 化できる。外部ツール不要。

```bash
qlmanage -t -s 512 -o . icon.svg && mv icon.svg.png icon-512.png
```

**小さい表示で判別できるかを必ず確かめる。** チャンネル一覧やメッセージ左のアイコンは実寸 20〜36px。
要素を詰め込むと潰れて汎用アイコンに見える。40px に縮小して目視するのが早い。

```bash
sips -Z 40 --out check.png icon-512.png
```

背景色はマニフェストの `background_color` と揃えると、App 詳細画面で浮かない。

## この構成でできないこと

- **メンションへの応答**。`app_mentions:read` とイベント購読、そしてイベントを受け取る常駐プロセス
  （Socket Mode か公開エンドポイント）が要る。GitHub Actions は常駐できないので不可
- **メッセージの読み取り**。`channels:history` が要る。ポーリングで代替する場合、
  CI の課金は**ジョブ単位で1分未満切り上げ**なので、実行回数がそのままコストになる
  （5分間隔・24時間なら月8,640分）
- **Slack Connect（外部共有チャンネル）への投稿**
