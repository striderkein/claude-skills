📝 新規スキル: `git-skip-worktree`

追跡中ファイルの変更が `git status` / `git diff` に出ない時の診断と、`skip-worktree` / `assume-unchanged` ビットの ON/OFF 切り替え。

**発動トリガー**
「diff が出ない」「変更が検知されない」「git が変更を無視する」「status に出ない」「skip-worktree」「assume-unchanged」「ローカル変更を git から隠す」「コミット対象から外す」等

**2 ビットの違い**
- `assume-unchanged` … stat チェック省略の性能最適化向け。git 都合で勝手に解除されうる
- `skip-worktree` … 意図的なローカル差分維持向け。git 操作で解除されにくい（設定ファイルのローカル差分隠しはこっち推奨）

**状態の見方** — `git ls-files -v <path>` のタグ
- `H` = 通常追跡
- `S` = skip-worktree のみ
- 小文字（`s`/`h` 等）= assume-unchanged

**手順 3 ステップ**
1. 診断 — `check-ignore` / `ls-files -v` で原因切り分け
2. 解除（diff 出す）
   ```bash
   git update-index --no-skip-worktree "$F"
   git update-index --no-assume-unchanged "$F"
   ```
3. 再隠し（diff 消す）— 元タグを確認し、立ってたビットだけ戻す
   ```bash
   git update-index --skip-worktree "$F"   # 元が S の場合
   ```

配置: `~/.claude/skills/git-skip-worktree/SKILL.md`
