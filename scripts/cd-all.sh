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

active_cwd=$(active_pane_cwd)
_mux=$(broadcast_multiplexer)

# display-popup -E propagates exit status but NOT stdout.
# Use a temp file to capture the popup's output.
_out=$(mktemp "${TMPDIR:-/tmp}/broadcast-cd.XXXXXX") || die "failed to create temp file"
trap 'rm -f "$_out"' EXIT

# Cancel with the same message surface as the tmux path.
_cancelled() {
  if [ "$_mux" = "herdr" ]; then
    printf 'cd-all: cancelled\n' >&2
  else
    tmux display-message "cd-all: cancelled"
  fi
  exit 0
}

if [ "$mode" = "picker" ]; then
  require_picker_engine
  if [ "$_mux" = "herdr" ]; then
    bash "$SCRIPT_DIR/picker.sh" "$active_cwd" > "$_out" || true
  else
    tmux display-popup \
      -E -w 60% -h 40% \
      -T "pick directory" \
      "bash '$SCRIPT_DIR/picker.sh' $(shell_quote "$active_cwd") > '$_out'" || true
  fi
  target=$(cat "$_out" 2>/dev/null || true)
  [ -z "$target" ] && _cancelled
else
  # Pre-fill with the parent directory so Tab browsing starts one level up.
  active_parent=$(dirname "$active_cwd")
  [ "$active_parent" = "/" ] || active_parent="$active_parent/"
  if [ "$_mux" = "herdr" ]; then
    bash "$SCRIPT_DIR/popup.sh" "$active_parent" > "$_out" || true
  else
    tmux display-popup \
      -E -w 40% -h 10% \
      -T "cd all panes" \
      "bash '$SCRIPT_DIR/popup.sh' $(shell_quote "$active_parent") > '$_out'" || true
  fi
  chosen=$(cat "$_out" 2>/dev/null || true)
  [ -z "$chosen" ] && _cancelled
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
