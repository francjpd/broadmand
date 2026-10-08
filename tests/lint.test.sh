#!/usr/bin/env bash
# tests/lint.test.sh — bash -n on every shell file, plus ShellCheck.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

checked=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  checked=$((checked + 1))
  rel=${f#"$REPO_DIR"/}
  if err=$(bash -n "$f" 2>&1); then
    _pass "bash -n $rel"
  else
    _fail "bash -n $rel: $err"
  fi
done < <(find "$REPO_DIR" -type f \
  \( -name '*.sh' -o -name '*.bash' -o -name '*.tmux' \) \
  -not -path '*/.git/*' | sort)

if [ "$checked" -eq 0 ]; then
  _fail "no shell files found to lint"
fi

if command -v shellcheck >/dev/null 2>&1; then
  # Run from the repo root so ShellCheck picks up .shellcheckrc.
  if sc_out=$(cd "$REPO_DIR" && shellcheck \
    tests/*.sh \
    broadmand.tmux broadmand.bash defaults.sh keybinds.sh scripts/*.sh 2>&1); then
    _pass "shellcheck is clean"
  else
    _fail "shellcheck: $sc_out"
  fi
else
  printf '  note shellcheck not installed; skipping shellcheck\n'
  _pass "shellcheck skipped (not installed)"
fi
