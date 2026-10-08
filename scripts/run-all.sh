#!/usr/bin/env bash
# scripts/run-all.sh — broadcast a free-form shell command to every pane
# in the active window.
#
# Usage:
#   run-all.sh
#
# Opens an empty single-line popup, then broadcasts the typed command
# via broadcast.sh to all panes in the active window.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=util.sh
. "$SCRIPT_DIR/util.sh"

# display-popup -E propagates exit status but NOT stdout.
# Use a temp file to capture the popup's output.
_out=$(mktemp "${TMPDIR:-/tmp}/broadmand-run.XXXXXX") || die "failed to create temp file"
trap 'rm -f "$_out"' EXIT

# Run the popup from the active pane's cwd so Tab completion resolves
# relative paths the same way the user's shell would.
active_cwd=$(tmux display-message -p '#{pane_current_path}')

tmux display-popup \
  -E -w 60% -h 15% \
  -T "broadcast command" \
  "bash '$SCRIPT_DIR/popup.sh' '' $(shell_quote "$active_cwd") > '$_out'" || true

command=$(cat "$_out" 2>/dev/null || true)
[ -z "$command" ] && { tmux display-message "run-all: cancelled"; exit 0; }

bash "$SCRIPT_DIR/broadcast.sh" "$command" --include-active
