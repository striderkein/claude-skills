#!/usr/bin/env bash
# 本人の GitHub 上の発言を skills/my-voice/corpus/ に集め直す（corpus/ は gitignore 済み。コミットしない）。
# 使い方: tools/collect-corpus.sh [login] [owner/repo ...]
# 例:     tools/collect-corpus.sh striderkein <owner>/<repo> striderkein/dotfiles
# 出力:   corpus/<owner>_<repo>.{issues,icomments,rcomments}.jsonl
#         各行に ai（AI が書いた印の有無）を付ける。印が無くても AI の文のことはある。
set -u
LOGIN="${1:-striderkein}"; shift || true
REPOS="${*:-striderkein/dotfiles striderkein/Curriculum-Vitae striderkein/dev-wisdom striderkein/striderkein.github.io}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/corpus"; mkdir -p "$OUT"
AI='claude-projects-attribution|Generated (by|with) \\[?Claude|claude\\.ai/code|Co-Authored-By: Claude'

page_all() { # $1 = API path（? を含む）、$2 = jq フィルタ。取れなかったら 1 を返す
  local p=1 raw n
  while :; do
    raw=$(gh api "$1&per_page=100&page=$p" 2>/dev/null) || { sleep 3; raw=$(gh api "$1&per_page=100&page=$p" 2>/dev/null) || return 1; }
    n=$(echo "$raw" | jq 'length') || return 1
    echo "$raw" | jq -c "$2" || return 1
    [ "$n" -lt 100 ] && return 0; p=$((p+1))
  done
}

# 取り終えてから差し替える。途中で失敗したら、手元の集め済みの分を残す
collect() { # $1 = 出力先、$2 = API path、$3 = jq フィルタ
  local tmp="$1.tmp"
  if page_all "$2" "$3" > "$tmp"; then mv "$tmp" "$1"; else rm -f "$tmp"; echo "取れなかった: $2（$1 はそのまま）" >&2; FAILED=1; fi
}

FAILED=0

for r in $REPOS; do
  f="$OUT/$(echo "$r" | tr / _)"
  collect "$f.issues.jsonl" "repos/$r/issues?creator=$LOGIN&state=all" \
    ".[] | {n:.number, pr:(.pull_request!=null), t:.title, b:(.body//\"\"), at:.created_at} | .ai=(.b|test(\"$AI\";\"i\"))"
  collect "$f.icomments.jsonl" "repos/$r/issues/comments?sort=created" \
    ".[] | select(.user.login==\"$LOGIN\") | {u:.issue_url, b:(.body//\"\"), at:.created_at} | .ai=(.b|test(\"$AI\";\"i\"))"
  collect "$f.rcomments.jsonl" "repos/$r/pulls/comments?sort=created" \
    ".[] | select(.user.login==\"$LOGIN\") | {u:.pull_request_url, path:.path, b:(.body//\"\"), at:.created_at} | .ai=(.b|test(\"$AI\";\"i\"))"
  echo "$r: issues/PR $(cat "$f.issues.jsonl" 2>/dev/null | wc -l)  comments $(cat "$f.icomments.jsonl" 2>/dev/null | wc -l)  review $(cat "$f.rcomments.jsonl" 2>/dev/null | wc -l)"
done
exit "$FAILED"
