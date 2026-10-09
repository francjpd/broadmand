#!/usr/bin/env bash
# scripts/broadcast.sh — run a shell line in every pane of the active window.
# Part of broadmand.
#
# Usage:
#   broadcast.sh "<shell-line>" [--include-active] [--dry-run]
#
# Skips panes whose current command is in the @broadcast-excluded list
# and panes that are currently in copy mode.
#
# The loop reads pane ids through process substitution so the sent/skipped
# counters stay in this shell instead of dying in a pipeline subshell.
# In --dry-run mode the [done] summary is printed to stdout; otherwise the
# summary is shown in the tmux status line with display-message, because
# run-shell discards stderr.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=util.sh
. "$SCRIPT_DIR/util.sh"

[ $# -ge 1 ] || die "usage: broadcast.sh <shell-line> [--include-active] [--dry-run]"

line="$1"; shift
include_active=0
dry_run=0
for a in "$@"; do
  case "$a" in
    --include-active) include_active=1 ;;
    --dry-run)        dry_run=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done

EXCLUDED=$(broadcast_excluded)
PANE_DELAY_MS=$(broadcast_pane_delay)
export PANE_DELAY_MS

active_id=$(active_pane_id)
sent=0
skipped=0

while IFS= read -r pid; do
  [ -n "$pid" ] || continue

  if [ "$pid" != "$active_id" ] || [ "$include_active" = "1" ]; then
    : # keep going
  else
    skipped=$((skipped+1))
    printf '[skip ] pane=%s reason=active-pane\n' "$pid"
    continue
  fi

  ex=$(pane_excluded "$pid" "$EXCLUDED")
  if [ "$ex" = "yes" ]; then
    skipped=$((skipped+1))
    cmd=$(pane_command "$pid")
    printf '[skip ] pane=%s reason=excluded(%s)\n' "$pid" "$cmd"
    continue
  fi

  if [ "$(pane_in_mode "$pid")" = "yes" ]; then
    skipped=$((skipped+1))
    printf '[skip ] pane=%s reason=in-copy-mode\n' "$pid"
    continue
  fi

  if [ "$dry_run" = "1" ]; then
    printf '[send ] pane=%s line=%q\n' "$pid" "$line"
    sent=$((sent+1))
    continue
  fi

  send_to_pane "$pid" "$line"
  sent=$((sent+1))
done < <(active_pane_ids)

# Return focus to the originally active pane. Herdr's pane send commands do
# not move focus, so only the tmux path needs to restore it.
if [ "$(broadcast_multiplexer)" = "tmux" ]; then
  tmux select-pane -t "$active_id" >/dev/null 2>&1 || true
fi

if [ "$dry_run" = "1" ]; then
  printf '[done ] sent=%d skipped=%d\n' "$sent" "$skipped"
else
  broadcast_status "broadmand: sent=$sent skipped=$skipped"
fi
