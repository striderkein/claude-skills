#!/bin/zsh
# 空き容量が閾値を割っていたら、disk-cleanup スキルの「安全段階」だけを無人で走らせる。
# launchd から定期起動される前提（登録は install-auto.sh）。手で叩いてもよい。
#
# 自動で消すもの（再取得できるか、作業の痕跡が残らないものだけ）:
#   1. 再 DL できるキャッシュ (uv / puppeteer / chrome-devtools-mcp / node-gyp / npm _cacache / Yarn) + brew cleanup
#   2. docker system prune -a -f（--volumes は付けない。DB などの永続層を守るため）
#   3. AUTO_CLEANUP_REPOS に挙げたリポジトリの .claude/worktrees/ 配下の worktree のうち、次をすべて満たすもの
#      - ローカル HEAD が「マージ済み PR のマージ時 head」の祖先、または既定ブランチに取り込み済みで独自コミット 0
#      - 未コミット変更・未追跡ファイルが無い
#      - どのプロセスの cwd にもなっていない
#      ローカルブランチは消さない（万一の取りこぼしもブランチから復元できる）
# 自動で消さないもの: node_modules 一括削除、ms-playwright、pnpm store、手動 worktree、ブラウザのデータ。
# 掃除しても閾値に届かなければ、通知で対話の /disk-cleanup を促す。
#
# 設定: ${STATE_DIR}/config（zsh として source する。雛形は assets/auto-cleanup.config.example）
# 環境変数（試験用。config より優先）:
#   THRESHOLD_GB : 発動閾値（既定 15）
#   DRY_RUN=1    : 削除せず、消す予定のものだけログに出す
#   NO_NOTIFY=1  : 通知しない
# 停止: touch ${STATE_DIR}/DISABLED
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

STATE_DIR="${DISK_AUTO_CLEANUP_DIR:-${HOME}/.claude/disk-auto-cleanup}"
mkdir -p "${STATE_DIR}/logs"
[[ -f "${STATE_DIR}/DISABLED" ]] && exit 0

# config の既定値。環境変数で渡された値は config で上書きさせない
_env_threshold="${THRESHOLD_GB:-}"
AUTO_CLEANUP_REPOS=()
THRESHOLD_GB=15
SLACK_BOT_TOKEN=""
SLACK_CHANNEL=""
[[ -f "${STATE_DIR}/config" ]] && source "${STATE_DIR}/config"
[[ -n "$_env_threshold" ]] && THRESHOLD_GB="$_env_threshold"
DRY_RUN="${DRY_RUN:-0}"

# df はスナップショットや purgeable 領域の扱いで実態とずれるので、APFS コンテナの空きで測る
free_bytes() { diskutil info / | awk -F'[()]' '/Container Free Space/{split($2,a," "); print a[1]}'; }
gb() { echo $(( $1 / 1000000000 )); }

BEFORE="$(free_bytes)"
[[ -z "$BEFORE" ]] && { echo "空き容量を取得できない" >&2; exit 1; }
if (( BEFORE >= THRESHOLD_GB * 1000000000 )); then
  echo "$(date '+%F %T') free=$(gb $BEFORE)GB >= ${THRESHOLD_GB}GB, skip" >> "${STATE_DIR}/logs/check.log"
  exit 0
fi

LOG="${STATE_DIR}/logs/run-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') start: free=$(gb $BEFORE)GB threshold=${THRESHOLD_GB}GB dry_run=${DRY_RUN} ==="

del() { if [[ "$DRY_RUN" == 1 ]]; then echo "[dry] rm -rf $*"; else rm -rf -- "$@"; fi; }

# 1) キャッシュ
del "${HOME}/.cache/uv" "${HOME}/.cache/puppeteer" "${HOME}/.cache/chrome-devtools-mcp" \
    "${HOME}/Library/Caches/node-gyp" "${HOME}/Library/Caches/Yarn" "${HOME}/.npm/_cacache"
if [[ "$DRY_RUN" != 1 ]] && command -v brew >/dev/null; then brew cleanup --prune=all >/dev/null 2>&1; fi
echo "caches: done"

# 2) Docker（daemon が動いている時だけ）
DOCKER_MSG="daemon 停止中のためスキップ"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == 1 ]]; then DOCKER_MSG="[dry] prune"; else
    DOCKER_MSG="$(docker system prune -a -f 2>&1 | grep 'Total reclaimed space' || echo 'prune 実行')"
  fi
fi
echo "docker: ${DOCKER_MSG}"

# 3) マージ済み worktree
WT_COUNT=0
WT_LIST="${STATE_DIR}/logs/.wt"
: > "$WT_LIST"
BUSY="$(lsof -a -d cwd 2>/dev/null | awk '{print $NF}' | sort -u)"
for REPO in "${AUTO_CLEANUP_REPOS[@]}"; do
  [[ -d "${REPO}/.git" ]] || { echo "skip (not a git repo): ${REPO}"; continue; }
  cd "$REPO" || continue
  DEFAULT="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  DEFAULT="${DEFAULT:-origin/main}"
  git fetch origin "${DEFAULT#origin/}" --quiet 2>/dev/null
  # ブランチ名 → マージ時の head SHA。名前の一致だけで消すと、マージ後に積んだローカルコミットを持つ worktree を巻き込む
  PRS=""
  if command -v gh >/dev/null; then
    PRS="$(gh pr list --state merged --author @me --limit 1000 --json headRefName,headRefOid \
           -q '.[]|"\(.headRefName)\t\(.headRefOid)"' 2>/dev/null)"
  fi
  git worktree list --porcelain \
  | awk '/^worktree /{p=substr($0,10)} /^branch /{b=$0; sub(/^branch refs\/heads\//,"",b); print p"\t"b} /^detached$/{print p"\t"}' \
  | while IFS=$'\t' read -r p b; do
      [[ "$p" == "${REPO}/.claude/worktrees/"?* ]] || continue
      print -r -- "$BUSY" | grep -q -- "^${p}\(/\|$\)" && continue
      [[ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]] && continue
      ref="${b:-$(git -C "$p" rev-parse HEAD 2>/dev/null)}"
      [[ -z "$ref" ]] && continue
      ok=0
      if [[ -n "$b" ]]; then
        for oid in ${(f)"$(print -r -- "$PRS" | awk -F'\t' -v b="$b" '$1==b{print $2}')"}; do
          git merge-base --is-ancestor "$ref" "$oid" 2>/dev/null && { ok=1; break; }
        done
      fi
      if (( ! ok )) && git merge-base --is-ancestor "$ref" "$DEFAULT" 2>/dev/null \
         && [[ "$(git rev-list --count "${DEFAULT}..${ref}" 2>/dev/null)" == 0 ]]; then ok=1; fi
      (( ok )) || continue
      if [[ "$DRY_RUN" == 1 ]]; then echo "[dry] worktree remove $p"; else
        git worktree remove --force "$p" 2>/dev/null
        # node_modules が大きいと 1 回の rm で "Directory not empty" が残ることがあるので繰り返す
        for _ in 1 2 3; do [[ -e "$p" ]] && rm -rf -- "$p" 2>/dev/null; done
      fi
      echo "worktree: ${p}"
    done >> "$WT_LIST"
  git worktree prune
done
cat "$WT_LIST"
WT_COUNT=$(grep -c '^worktree: ' "$WT_LIST")

AFTER="$(free_bytes)"
SUMMARY="空き $(gb $BEFORE)GB → $(gb $AFTER)GB（閾値 ${THRESHOLD_GB}GB）
- キャッシュ + brew cleanup
- Docker: ${DOCKER_MSG}
- マージ済み worktree 削除: ${WT_COUNT} 個"
if (( AFTER < THRESHOLD_GB * 1000000000 )); then
  SUMMARY="${SUMMARY}
:warning: まだ閾値未満。対話セッションで \`/disk-cleanup\`（node_modules 一括削除など）を検討"
fi
echo "$SUMMARY"
echo "=== $(date '+%F %T') end ==="

[[ "${NO_NOTIFY:-0}" == 1 ]] && exit 0
osascript -e "display notification \"空き $(gb $BEFORE)GB → $(gb $AFTER)GB\" with title \"ディスク自動掃除\" sound name \"Ping\"" >/dev/null 2>&1
if [[ "$SLACK_BOT_TOKEN" == xox* && -n "$SLACK_CHANNEL" ]]; then
  TEXT=":broom: *ディスク自動掃除を実行しました*
${SUMMARY}

ログ: \`${LOG}\` / 停止: \`touch ${STATE_DIR}/DISABLED\`"
  curl -sS -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" -H 'Content-type: application/json; charset=utf-8' \
    --data "$(/usr/bin/python3 -c 'import json,sys;print(json.dumps({"channel":sys.argv[1],"text":sys.argv[2]}))' "$SLACK_CHANNEL" "$TEXT")" >/dev/null
fi
