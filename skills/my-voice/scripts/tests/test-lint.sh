#!/usr/bin/env bash
# lint-voice.sh の回帰テスト。bad.md は ERROR で落ち、good.md は通ること。
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LINT="$DIR/../lint-voice.sh"
fail=0
if bash "$LINT" "$DIR/fixtures/bad.md" >/dev/null; then echo "NG: bad.md が通ってしまった"; fail=1; else echo "ok: bad.md は落ちる"; fi
if bash "$LINT" "$DIR/fixtures/good.md" >/dev/null; then echo "ok: good.md は通る"; else echo "NG: good.md が落ちた"; bash "$LINT" "$DIR/fixtures/good.md"; fail=1; fi
out=$(bash "$LINT" "$DIR/fixtures/good.md")
if echo "$out" | grep -q "WARN"; then echo "NG: good.md に WARN が出た"; echo "$out"; fail=1; else echo "ok: good.md は WARN なし"; fi
exit $fail
