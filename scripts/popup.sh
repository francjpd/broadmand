#!/usr/bin/env bash
# scripts/popup.sh — reusable single-line input modal with Tab completion.
# Part of broadmand.
#
# Usage (inside a tmux display-popup -E):
#   popup.sh "<default>" [<cwd>]
#
# Prints the chosen value to stdout.
# Exits 0 with empty stdout if cancelled (Esc or Ctrl-C), non-zero on read error.
#
# Keys:
#   Enter  — submit
#   Esc    — cancel (clears any default/input and closes the modal)
#   Tab    — cycle through file-name completions (zsh-style menu-complete)

set -euo pipefail

default="${1:-}"
start_dir="${2:-}"

# Change into the caller's working directory so filename completion
# resolves relative to the active pane's cwd rather than the plugin dir.
if [ -n "$start_dir" ] && [ -d "$start_dir" ]; then
  cd "$start_dir" || true
fi

# Build a temporary INPUTRC that makes Tab feel like zsh menu-complete:
# - Tab cycles forward through matches, Shift-Tab cycles backward.
# - If no common prefix can be inserted, show the full list immediately.
# - Append file-type indicators (/ for dirs, * for executables, etc.).
_inputrc=$(mktemp "${TMPDIR:-/tmp}/broadmand-popup-inputrc.XXXXXX") || true
if [ -n "${_inputrc:-}" ]; then
  {
    printf 'set show-all-if-ambiguous on\n'
    printf 'set show-all-if-unmodified on\n'
    printf 'set visible-stats on\n'
    printf 'set colored-stats on\n'
    printf 'set menu-complete-display-prefix on\n'
    printf 'TAB: menu-complete\n'
    printf '"\\e[Z": menu-complete-backward\n'
  } > "$_inputrc"
  # Also set a shell variable so the trap can locate the file.
  BROADCAST_POPUP_INPUTRC="$_inputrc"
  export INPUTRC="$BROADCAST_POPUP_INPUTRC"
fi

# Make Esc clear the line and send EOF, so read -e exits with empty output.
# Ctrl-C is also bound to abort cleanly.
bind '"\e": "\C-a\C-k\C-d"' 2>/dev/null || true
bind '"\C-c": abort' 2>/dev/null || true

# read -e enables readline with Tab completion (filename completion by default).
# -i "$default" pre-seeds the edit buffer so the user sees it and can edit.
# macOS ships bash 3.2, whose read builtin does not support -i; using it
# there makes the popup exit immediately. Omit -i on bash < 4.
# -p writes the prompt to stderr (visible in the popup terminal).
on_exit() {
  if [ -n "${BROADCAST_POPUP_INPUTRC:-}" ]; then
    rm -f "$BROADCAST_POPUP_INPUTRC" 2>/dev/null || true
  fi
}
trap on_exit EXIT

if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  if IFS= read -r -e -i "$default" -p '> ' ans; then
    printf '%s\n' "$ans"
  else
    printf ''
    exit 0
  fi
else
  if IFS= read -r -e -p '> ' ans; then
    printf '%s\n' "$ans"
  else
    printf ''
    exit 0
  fi
fi
