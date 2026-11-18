#!/usr/bin/env bash
# react.sh の回帰テスト。gh を偽物に差し替えるのでネットワークには出ない。
#   bash test-react.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../react.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 偽の gh。呼ばれた引数を calls.log に書き、FAKE_* 環境変数で応答を変える。
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$*" in
  "api user --jq .login")
    echo "${FAKE_ME:-me}" ;;
  "api -X POST "*"/reactions -f content="*)
    [ "${FAKE_POST_FAIL:-}" = 1 ] && exit 1
    echo "${*##*content=}" ;;
  "api "*"/reactions?"*)
    printf '%s' "${FAKE_ALREADY:-}" ;;
  "api repos/"*)
    echo "${FAKE_AUTHOR:-alice} ${FAKE_TYPE:-User}" ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$work/bin/gh"

pass=0; fail=0
check() { # name expected_exit expected_stdout_substring expected_call_substring(空なら見ない) unexpected_call_substring(空なら見ない)
  local name=$1 want_code=$2 want_out=$3 want_call=$4 not_call=$5
  if [ "$code" != "$want_code" ]; then echo "FAIL $name: exit=$code want=$want_code out=$out"; fail=$((fail+1)); return; fi
  if [ -n "$want_out" ] && [[ $out != *"$want_out"* ]]; then echo "FAIL $name: stdout に '$want_out' が無い: $out"; fail=$((fail+1)); return; fi
  if [ -n "$want_call" ] && ! grep -qF -- "$want_call" "$FAKE_LOG"; then echo "FAIL $name: gh に '$want_call' が渡っていない"; cat "$FAKE_LOG"; fail=$((fail+1)); return; fi
  if [ -n "$not_call" ] && grep -qF -- "$not_call" "$FAKE_LOG"; then echo "FAIL $name: gh に '$not_call' が渡ってしまった"; cat "$FAKE_LOG"; fail=$((fail+1)); return; fi
  echo "PASS $name"; pass=$((pass+1))
}
run() { # 各ケースの前にログと環境を初期化してから react.sh を呼ぶ
  export FAKE_LOG="$work/calls.log"; : > "$FAKE_LOG"
  out=$(PATH="$work/bin:$PATH" bash "$script" "$@" 2>&1); code=$?
}
reset_env() { unset FAKE_ME FAKE_AUTHOR FAKE_TYPE FAKE_ALREADY FAKE_POST_FAIL; }

ISSUE_URL='https://github.com/acme/app/issues/12#issuecomment-111'
PR_CONV_URL='https://github.com/acme/app/pull/34#issuecomment-222'
REVIEW_URL='https://github.com/acme/app/pull/34#discussion_r333'

# Issue の会話欄のコメントに 👍 を付けると issues/comments/<id>/reactions に POST する
reset_env; run "$ISSUE_URL" +1
check "issue コメントに +1" 0 "+1 111 alice" "api -X POST repos/acme/app/issues/comments/111/reactions -f content=+1" ""

# PR の会話欄のコメントも issues/comments を使う
reset_env; run "$PR_CONV_URL" eyes
check "PR 会話欄のコメントに eyes" 0 "eyes 222 alice" "api -X POST repos/acme/app/issues/comments/222/reactions -f content=eyes" ""

# PR の行コメントは pulls/comments を使う
reset_env; run "$REVIEW_URL" eyes
check "PR 行コメントに eyes" 0 "eyes 333 alice" "api -X POST repos/acme/app/pulls/comments/333/reactions -f content=eyes" "issues/comments/333"

# 自分のコメントには付けない（POST しない）
reset_env; FAKE_ME=alice; export FAKE_ME; run "$ISSUE_URL" +1
check "自分のコメントは付けない" 3 "自分のコメント" "" "api -X POST"

# type が Bot のコメントには付けない
reset_env; FAKE_AUTHOR=renovate; FAKE_TYPE=Bot; export FAKE_AUTHOR FAKE_TYPE; run "$ISSUE_URL" +1
check "Bot 型のコメントは付けない" 3 "bot のコメント" "" "api -X POST"

# login が [bot] で終わるコメントにも付けない
reset_env; FAKE_AUTHOR='dependabot[bot]'; export FAKE_AUTHOR; run "$ISSUE_URL" eyes
check "[bot] 名のコメントは付けない" 3 "bot のコメント" "" "api -X POST"

# 自分が同じリアクションを付け済みなら POST しない
reset_env; FAKE_ALREADY=9999; export FAKE_ALREADY; run "$ISSUE_URL" +1
check "付け済みなら二重に付けない" 0 "付け済み" "reactions?content=+1" "api -X POST"

# +1 / eyes 以外のリアクションは引数エラー（gh を呼ばない）
reset_env; run "$ISSUE_URL" heart
check "+1/eyes 以外は拒否" 2 "+1 か eyes" "" "api"

# コメントを指さない URL（Issue 本体）は引数エラー
reset_env; run 'https://github.com/acme/app/issues/12' +1
check "コメント以外の URL は拒否" 2 "対応していない URL" "" "api"

# 引数の数が違えば usage
reset_env; run "$ISSUE_URL"
check "引数不足は usage" 2 "usage" "" "api"

# POST が失敗したら 4
reset_env; FAKE_POST_FAIL=1; export FAKE_POST_FAIL; run "$ISSUE_URL" +1
check "POST 失敗は 4" 4 "付けられない" "api -X POST" ""

echo "---"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
