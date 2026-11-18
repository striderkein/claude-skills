#!/usr/bin/env bash
# 他人の GitHub コメントにリアクションを付ける。
#   react.sh <コメントの URL> <+1|eyes>
# 自分と bot のコメントには付けない。自分がすでに同じリアクションを付けていれば何もしない。
# 終了コード: 0 付けた/付いていた, 2 引数不正, 3 自分か bot なので付けない, 4 API 失敗
set -euo pipefail

usage() { echo "usage: react.sh <comment-url> <+1|eyes>" >&2; exit 2; }

[ $# -eq 2 ] || usage
url=$1
content=$2

case "$content" in
  +1|eyes) ;;
  *) echo "リアクションは +1 か eyes だけ: $content" >&2; exit 2 ;;
esac

# URL から owner / repo / 種別 / コメント ID を取る
re_issue='^https://github\.com/([^/]+)/([^/]+)/(issues|pull)/[0-9]+#issuecomment-([0-9]+)$'
re_review='^https://github\.com/([^/]+)/([^/]+)/pull/[0-9]+#discussion_r([0-9]+)$'
if [[ $url =~ $re_issue ]]; then
  owner=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; id=${BASH_REMATCH[4]}
  path="repos/$owner/$repo/issues/comments/$id"
elif [[ $url =~ $re_review ]]; then
  owner=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; id=${BASH_REMATCH[3]}
  path="repos/$owner/$repo/pulls/comments/$id"
else
  echo "対応していない URL: $url" >&2
  echo "issuecomment-<id> か discussion_r<id> を含むコメントの URL を渡す" >&2
  exit 2
fi

me=$(gh api user --jq .login) || { echo "gh api user に失敗" >&2; exit 4; }

author=$(gh api "$path" --jq '.user.login + " " + .user.type') || { echo "コメントを取得できない: $path" >&2; exit 4; }
login=${author% *}
type=${author##* }

if [ "$login" = "$me" ]; then
  echo "自分のコメントなので付けない: $login" >&2; exit 3
fi
if [ "$type" = "Bot" ] || [[ $login == *"[bot]" ]]; then
  echo "bot のコメントなので付けない: $login" >&2; exit 3
fi

# 自分が同じリアクションをすでに付けていれば何もしない
already=$(gh api "$path/reactions?content=$content&per_page=100" --paginate \
  --jq ".[] | select(.user.login == \"$me\") | .id") || { echo "リアクションを取得できない" >&2; exit 4; }
if [ -n "$already" ]; then
  echo "$content $id $login（付け済み）"
  exit 0
fi

gh api -X POST "$path/reactions" -f content="$content" --jq .content >/dev/null \
  || { echo "リアクションを付けられない: $path" >&2; exit 4; }
echo "$content $id $login"
