---
name: git-skip-worktree
description: 追跡中ファイルの変更が git status/diff に出ない時の診断と、skip-worktree / assume-unchanged ビットの ON/OFF 切り替え。「diff が出ない」「変更が検知されない」「git が変更を無視する」「status に出ない」「skip-worktree」「assume-unchanged」「ローカル変更を git から隠す」「コミット対象から外す」等で発動。
---

# git-skip-worktree

追跡中（tracked）ファイルなのに編集が `git status` / `git diff` に出てこない原因を診断し、`skip-worktree` / `assume-unchanged` ビットを切り替える skill。

`.gitignore` は **追跡前** のファイルにしか効かない。すでに追跡中のファイルをローカルで編集しつつコミット対象から外す用途には、この 2 ビットを使う（例: `CLAUDE.md` / `.env` / 設定ファイルのローカル差分隠し）。

## 2 ビットの違い

| ビット | 意味 | 主用途 |
|---|---|---|
| `assume-unchanged` | 「変更してないはず」と git に告げて stat チェックを省略。性能最適化向け。git 側の都合で勝手に解除されうる | 巨大ファイルの stat 省略 |
| `skip-worktree` | 「worktree 側を触るな」。意図的なローカル差分維持向けで、git 操作で解除されにくい | 設定ファイルのローカル差分隠し（推奨） |

どちらが立っていても worktree の編集は status/diff に出なくなる。

## 状態の見方

`git ls-files -v <path>` のタグ文字で判定する:

- `H` … 通常追跡（ビットなし）
- `S`（大文字）… skip-worktree のみ ON
- 小文字（`h`/`s` 等）… assume-unchanged ON（小文字化で表現。skip-worktree も同時 ON なら `s`）

例: `s CLAUDE.md` → そのファイルは隠し対象になっている。

## 実行手順

### Step 1: 診断（なぜ diff が出ないか）

対象ファイルパスを受け取り、原因を順に切り分ける:

```bash
F=<path>
echo "--- status ---";       git status --short "$F"
echo "--- check-ignore ---";  git check-ignore -v "$F"   # 出力あれば .gitignore 由来
echo "--- ls-files -v ---";   git ls-files -v "$F"        # 小文字/S なら隠しビット
echo "--- stage ---";         git ls-files -s "$F"        # mode/hash（追跡有無）
echo "--- file ---";          ls -la "$F"                 # symlink 等の確認
```

判定:
- `check-ignore` に出力 → `.gitignore` 由来（この skill の対象外、別途対応）
- `ls-files -v` が小文字 or `S` → **skip-worktree / assume-unchanged が原因**。Step 2 へ
- `ls-files -s` が空 → そもそも未追跡（`git add` 必要）

### Step 2: 隠しを解除（diff を出す）

どちらのビットも落とす（立っていないビットへの no-op は無害）:

```bash
git update-index --no-skip-worktree "$F"
git update-index --no-assume-unchanged "$F"
git ls-files -v "$F"   # 確認: H <path> になれば解除完了
```

### Step 3: 再び隠す（diff を消す）

元の状態に戻す。**Step 1 のタグを確認して、立っていたビットだけを立て直す**こと（両方無条件で立てない）:

- 元が `S`（skip-worktree）:
  ```bash
  git update-index --skip-worktree "$F"
  ```
- 元が assume-unchanged（小文字 `h` 等、`s` 以外の小文字）:
  ```bash
  git update-index --assume-unchanged "$F"
  ```

確認:
```bash
git ls-files -v "$F"   # 元のタグに戻ったか
```

## 一覧確認

隠し対象を棚卸ししたい時:

```bash
git ls-files -v | grep -E '^[a-z]' || echo "assume-unchanged: なし"
git ls-files -v | grep '^S'        || echo "skip-worktree: なし"
```

## 注意

- worktree 間でビットは共有されない（index ローカルの状態）。worktree ごとに設定が要る
- `skip-worktree` のままだと `git pull` / `merge` で上流がそのファイルを変えた時に競合・上書き挙動が分かりにくくなる。長期運用はファイル単位で意図を把握しておく
- コミットしたい差分まで隠れて事故る典型なので、「コミットしたいのに出ない」時はまず Step 1 で診断する
