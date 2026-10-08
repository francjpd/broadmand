#!/usr/bin/env bash
# tests/util.test.sh — unit tests for scripts/util.sh helpers.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

# Stub tmux so defaults.sh loads and tmux_opt calls do not explode.
STUB="$TMPDIR/unit-stub"
mkdir -p "$STUB"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/tmux"
chmod +x "$STUB/tmux"
PATH="$STUB:$PATH"

# shellcheck source=../scripts/util.sh
. "$REPO_DIR/scripts/util.sh"

# --- shell_quote ---
roundtrip() { eval "printf '%s' $(shell_quote "$1")"; }
assert_eq "shell_quote wraps a plain word" "'abc'" "$(shell_quote abc)"
assert_eq "shell_quote escapes an embedded quote" "'a'\\''b'" "$(shell_quote "a'b")"
assert_eq "shell_quote round-trips spaces" "a b" "$(roundtrip 'a b')"
assert_eq "shell_quote round-trips a single quote" "it's" "$(roundtrip "it's")"
# shellcheck disable=SC2016  # literal dollars/quotes are what is being tested
assert_eq "shell_quote round-trips metacharacters" '$HOME; rm -rf /' "$(roundtrip '$HOME; rm -rf /')"
assert_eq "shell_quote round-trips double quotes" 'say "hi"' "$(roundtrip 'say "hi"')"
assert_eq "shell_quote round-trips empty" "" "$(roundtrip '')"

# --- pane_excluded (override pane_command) ---
TEST_PANE_CMD=""
pane_command() { printf '%s\n' "$TEST_PANE_CMD"; }

TEST_PANE_CMD=vim
assert_eq "pane_excluded exact match" yes "$(pane_excluded p 'vim')"
assert_eq "pane_excluded trims surrounding whitespace" yes "$(pane_excluded p '  vim  , vi ')"
TEST_PANE_CMD=vim.9
assert_eq "pane_excluded matches with stripped extension" yes "$(pane_excluded p 'vim')"
TEST_PANE_CMD=bash
assert_eq "pane_excluded non-match" no "$(pane_excluded p 'vim, vi')"
assert_eq "pane_excluded empty list" no "$(pane_excluded p '')"
assert_eq "pane_excluded trims each entry" no "$(pane_excluded p ' vim ,vi,  less ')"
TEST_PANE_CMD=""
assert_eq "pane_excluded empty command is skipped" yes "$(pane_excluded p 'vim')"

# --- normalize_path ---
assert_eq "normalize_path relative" "/root/sub" "$(normalize_path sub /root)"
assert_eq "normalize_path strips trailing slash" "/root/sub" "$(normalize_path 'sub/' /root)"
assert_eq "normalize_path absolute" "/a/b" "$(normalize_path '/a/b/' /root)"
assert_eq "normalize_path keeps root" "/" "$(normalize_path '/' /root)"
assert_eq "normalize_path empty" "" "$(normalize_path '' /root)"
# shellcheck disable=SC2088  # a literal tilde is exactly what normalize_path must expand
assert_eq "normalize_path expands tilde" "$HOME/child" "$(normalize_path '~/child' /root)"

# --- find_fd ---
fdbin="$TMPDIR/fd-bin"
mkdir -p "$fdbin"
: > "$fdbin/fd"
chmod +x "$fdbin/fd"
assert_eq "find_fd prefers fd" fd "$(PATH="$fdbin" find_fd)"

fdfindbin="$TMPDIR/fdfind-bin"
mkdir -p "$fdfindbin"
: > "$fdfindbin/fdfind"
chmod +x "$fdfindbin/fdfind"
assert_eq "find_fd falls back to fdfind" fdfind "$(PATH="$fdfindbin" find_fd)"

nonebin="$TMPDIR/none-bin"
mkdir -p "$nonebin"
assert_eq "find_fd reports nothing when absent" "" "$(PATH="$nonebin" find_fd)"

# --- pane_in_mode (override tmux) ---
tmux() { printf '%s\n' "${TEST_IN_MODE:-}"; }
TEST_IN_MODE=0
assert_eq "pane_in_mode 0 is not in a mode" no "$(pane_in_mode p)"
TEST_IN_MODE=1
assert_eq "pane_in_mode 1 is in a mode" yes "$(pane_in_mode p)"
TEST_IN_MODE=2
assert_eq "pane_in_mode 2 (stacked modes) is in a mode" yes "$(pane_in_mode p)"
TEST_IN_MODE=""
assert_eq "pane_in_mode empty reply is not in a mode" no "$(pane_in_mode p)"
tmux() { return 1; }
assert_eq "pane_in_mode failed query is not in a mode" no "$(pane_in_mode p)"

# --- picker_engine_available / require_picker_engine ---
zbin="$TMPDIR/zoxide-bin"
mkdir -p "$zbin"
: > "$zbin/zoxide"
chmod +x "$zbin/zoxide"
assert_eq "engine fd available" yes "$(PATH="$fdbin" picker_engine_available fd)"
assert_eq "engine fd unavailable" no "$(PATH="$nonebin" picker_engine_available fd)"
assert_eq "engine zoxide available" yes "$(PATH="$zbin" picker_engine_available zoxide)"
assert_eq "engine zoxide falls back to fd" yes "$(PATH="$fdbin" picker_engine_available zoxide)"
assert_eq "engine both available" yes "$(PATH="$zbin" picker_engine_available both)"
assert_eq "engine both unavailable" no "$(PATH="$nonebin" picker_engine_available both)"
assert_eq "unknown engine unavailable" no "$(picker_engine_available bogus)"

if (
  PATH="$nonebin"
  export PATH
  broadcast_picker_engine() { echo fd; }
  require_picker_engine
) >/dev/null 2>&1; then
  _fail "require_picker_engine exits when the engine is missing"
else
  _pass "require_picker_engine exits when the engine is missing"
fi

if (
  PATH="$fdbin"
  export PATH
  broadcast_picker_engine() { echo fd; }
  require_picker_engine
) >/dev/null 2>&1; then
  _pass "require_picker_engine passes when the engine is present"
else
  _fail "require_picker_engine fails when the engine is present"
fi
