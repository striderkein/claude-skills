# claude-skills

[Claude Code](https://claude.com/claude-code) のユーザレベル skill 集。

`~/.claude/skills/` に置いて使う。特定の会社・プロジェクトに依存しない汎用スキルのみを収録している。

## 収録スキル

| Skill | 概要 |
|---|---|
| `adversarial-panel` | 複数モデルによる敵対的相互レビュー。パネリストが独立回答 → 相互批判 → ファシリテータが合意点・対立点・確信度を統合する |
| `dev-browser` | ページ状態を保持したブラウザ自動化 (navigate / click / fill / screenshot / extract) |
| `disk-cleanup` | macOS のディスク空き容量を最大化。Docker prune + 安全なキャッシュ削除 + `node_modules` 一括削除 |
| `git-skip-worktree` | 追跡中ファイルの変更が `git status` / `git diff` に出ない時の診断と、`skip-worktree` / `assume-unchanged` ビットの ON/OFF |
| `japanese-tech-writing` | 日本語の技術文書・書籍原稿の文章規範。整形、パラグラフライティング、論証の厳密さ、冗長の排除 |
| `slack-bot-setup` | 通知用 Slack App (bot) をマニフェストから作って投稿まで通す手順。マニフェスト検証で弾かれる項目、ハンドルからハイフンが落ちる仕様、投稿スクリプト同梱 |
| `voice-proxy` | 本人の声のクローン（合成音声）でテキストを代読し、仮想オーディオデバイス経由で会議アプリに流す |

## インストール

```sh
git clone git@github.com:striderkein/claude-skills.git
ln -s "$PWD/claude-skills/skills/<name>" ~/.claude/skills/<name>
```

あるいは使いたいスキルのディレクトリを `~/.claude/skills/` にコピーする。

## 設定

スキルによっては環境変数や設定ファイルが必要。

| Skill | 必要なもの |
|---|---|
| `slack-bot-setup` | `SLACK_BOT_TOKEN`、`assets/config.example.json` を元にした投稿先設定 |
| `voice-proxy` | `ELEVENLABS_API_KEY`、`ELEVENLABS_VOICE_ID`、仮想オーディオデバイス (BlackHole / VB-Cable) |

チャンネル ID やシート ID などの実値はリポジトリに含めず、各自の環境で設定すること。
