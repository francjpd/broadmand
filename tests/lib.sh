#!/usr/bin/env bash
# tests/lib.sh — shared helpers for the broadmand test suite.
# Source this from a *.test.sh file, then `trap finish EXIT`.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
export TESTS_DIR REPO_DIR

PASS=0
FAIL=0
FAILURES=()

_pass() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

_fail() {
  FAIL=$((FAIL + 1))
  FAILURES+=("$1")
  printf '  FAIL %s\n' "$1" >&2
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    _pass "$desc"
  else
    _fail "$desc (expected [$expected], got [$actual])"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) _pass "$desc" ;;
    *) _fail "$desc (missing [$needle] in [$haystack])" ;;
  esac
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) _fail "$desc (found [$needle] in [$haystack])" ;;
    *) _pass "$desc" ;;
  esac
}

# Start an isolated headless tmux server and point the `tmux` command at it.
# Sets TEST_TMUX_SOCK and TMUX so child scripts talk to the test server.
tmux_start() {
  : "${TEST_TMUX_SOCK:=broadmand-test-$$}"
  export TEST_TMUX_SOCK
  tmux -L "$TEST_TMUX_SOCK" -f /dev/null new-session -d -x 200 -y 50
  local sock
  sock=$(tmux -L "$TEST_TMUX_SOCK" display-message -p '#{socket_path}')
  export TMUX="$sock"
}

tmux_stop() {
  [ -n "${TEST_TMUX_SOCK:-}" ] || return 0
  tmux -L "$TEST_TMUX_SOCK" kill-server >/dev/null 2>&1 || true
}

finish() {
  local rc="${1:-$?}"
  if [ "$FAIL" -eq 0 ] && [ "$rc" -eq 0 ]; then
    printf 'PASS %s (%d assertions)\n' "$(basename "$0")" "$PASS"
    exit 0
  fi
  printf 'FAIL %s (%d passed, %d failed)\n' "$(basename "$0")" "$PASS" "$FAIL" >&2
  exit 1
}
