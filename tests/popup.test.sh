#!/usr/bin/env bash
# tests/popup.test.sh — pty-driven tests for scripts/popup.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

: "${BASH:=bash}"
: "${PYTHON:=python3}"

work="$TMPDIR/popup-work"
mkdir -p "$work/apple" "$work/apricot"

run_popup() {
  # run_popup <input-bytes> <outfile> : drives popup.sh in a pty and prints
  # whatever the pty emitted. The popup's stdout goes to <outfile>.
  local input="$1" outfile="$2" b64 cmd
  b64=$(printf '%s' "$input" | base64 | tr -d '\n')
  cmd="'$BASH' '$REPO_DIR/scripts/popup.sh' '' '$work' > '$outfile'"
  "$PYTHON" "$TESTS_DIR/ptydrive.py" --timeout 15 --input "$b64" -- \
    "$BASH" -c "$cmd"
}

if command -v "$PYTHON" >/dev/null 2>&1; then
  # Menu-complete: "ap" + Tab lists, then cycles apple/ -> apricot/.
  out1="$TMPDIR/popup-out1"
  rm -f "$out1"
  if run_popup "$(printf 'ap\t\t\t\r')" "$out1" >/dev/null 2>&1; then
    _pass "popup exits 0 on Enter"
  else
    _fail "popup did not exit 0 on Enter"
  fi
  result=$(cat "$out1" 2>/dev/null || true)
  assert_eq "Tab menu-complete cycles to the second directory" "apricot/" "$result"

  # Esc cancels and prints nothing.
  out2="$TMPDIR/popup-out2"
  rm -f "$out2"
  if run_popup "$(printf '\033')" "$out2" >/dev/null 2>&1; then
    _pass "popup exits 0 on Esc"
  else
    _fail "popup did not exit 0 on Esc"
  fi
  result2=$(cat "$out2" 2>/dev/null || true)
  assert_eq "Esc cancels with empty output" "" "$result2"
else
  printf '  note %s not found; skipping popup pty test\n' "$PYTHON"
  _pass "popup test skipped (no python3)"
fi
