#!/usr/bin/env bash
# scripts/cd-all.sh — broadcast `cd <path>` to every pane in the active window.
#
# Usage:
#   cd-all.sh picker     # fzf directory picker → broadcast directly
#   cd-all.sh freeform   # popup with Tab-completable input, pre-filled with cwd
#   cd-all.sh            # default: freeform

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=util.sh
. "$SCRIPT_DIR/util.sh"

mode="${1:-freeform}"
case "$mode" in
  freeform|picker) ;;
  *) die "unknown mode: $mode (expected freeform|picker)" ;;
esac

active_cwd=$(tmux display-message -p '#{pane_current_path}')

# display-popup -E propagates exit status but NOT stdout.
# Use a temp file to capture the popup's output.
_out=$(mktemp "${TMPDIR:-/tmp}/broadcast-cd.XXXXXX") || die "failed to create temp file"
trap 'rm -f "$_out"' EXIT

if [ "$mode" = "picker" ]; then
  require_picker_engine
  tmux display-popup \
    -E -w 60% -h 40% \
    -T "pick directory" \
    "bash '$SCRIPT_DIR/picker.sh' $(shell_quote "$active_cwd") > '$_out'" || true
  target=$(cat "$_out" 2>/dev/null || true)
  [ -z "$target" ] && { tmux display-message "cd-all: cancelled"; exit 0; }
else
  # Pre-fill with the parent directory so Tab browsing starts one level up.
  active_parent=$(dirname "$active_cwd")
  [ "$active_parent" = "/" ] || active_parent="$active_parent/"
  tmux display-popup \
    -E -w 40% -h 10% \
    -T "cd all panes" \
    "bash '$SCRIPT_DIR/popup.sh' $(shell_quote "$active_parent") > '$_out'" || true
  chosen=$(cat "$_out" 2>/dev/null || true)
  [ -z "$chosen" ] && { tmux display-message "cd-all: cancelled"; exit 0; }
  # Expand leading ~ but leave relative paths as-is (each pane resolves them).
  target="${chosen/#\~/$HOME}"
fi

# Build the shell line, safely quoted.
quoted=$(shell_quote "$target")
# Use 'builtin cd' to bypass zoxide and other cd hooks
# so the exact path is always used, not a fuzzy match.
line="builtin cd $quoted"

# Broadcast to ALL panes including the active one.
bash "$SCRIPT_DIR/broadcast.sh" "$line" --include-active
