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
  # Basic entry must work on every bash, including the macOS system bash 3.2
  # (this exercises popup.sh's read -e fallback, which omits -i there).
  out0="$TMPDIR/popup-out0"
  rm -f "$out0"
  if run_popup "$(printf 'hello world\r')" "$out0" >/dev/null 2>&1; then
    _pass "popup exits 0 on Enter"
  else
    _fail "popup did not exit 0 on Enter"
  fi
  assert_eq "popup returns the typed text" "hello world" \
    "$(cat "$out0" 2>/dev/null || true)"

  # menu-complete cycling and Esc-cancellation depend on GNU readline key
  # handling. The macOS system bash 3.2 ships an older readline that does
  # not honour these bindings, so assert them only where they are supported.
  if [ "$(uname -s)" = "Darwin" ] && [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    printf '  note macOS bash %s readline lacks menu-complete/Esc; skipping those assertions\n' \
      "${BASH_VERSION:-unknown}"
    _pass "menu-complete and Esc assertions skipped on macOS bash 3.2"
  else
    # Menu-complete: "ap" + Tab lists, then cycles apple/ -> apricot/.
    out1="$TMPDIR/popup-out1"
    rm -f "$out1"
    if run_popup "$(printf 'ap\t\t\t\r')" "$out1" >/dev/null 2>&1; then
      _pass "popup exits 0 on Enter after completion"
    else
      _fail "popup did not exit 0 on Enter after completion"
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
  fi
else
  printf '  note %s not found; skipping popup pty test\n' "$PYTHON"
  _pass "popup test skipped (no python3)"
fi
