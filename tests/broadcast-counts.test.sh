#!/usr/bin/env bash
# tests/broadcast-counts.test.sh — deterministic F1 regression test.
# The sent/skipped counters used to die in the pipeline subshell, so the
# [done] summary always read sent=0 skipped=0. --dry-run prints the summary
# to stdout, which makes that assertion possible without a real send.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${BASH:=bash}"

tmux_start
cleanup() {
  local rc=$?
  tmux_stop
  finish "$rc"
}
trap cleanup EXIT

tmux new-window -d -n counts "$BASH"
win=$(tmux list-windows -F '#{window_id} #{window_name}' \
  | awk '$2 == "counts" { print $1 }')
tmux split-window -t "$win" "$BASH"
tmux select-window -t "$win"
tmux select-pane -t "$(tmux list-panes -t "$win" -F '#{pane_id}' | head -n 1)"
sleep 1

out=$("$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --include-active --dry-run)
assert_contains "dry-run reports sends" "$out" "[send ]"
assert_contains "F1: summary reports the real sent count" "$out" "[done ] sent=2 skipped=0"

# An excluded pane must be counted as skipped, not silently dropped.
tmux set-option -g @broadcast-excluded 'sleep'
tmux split-window -t "$win" "exec sleep 300"
tmux select-pane -t "$(tmux list-panes -t "$win" -F '#{pane_id}' | head -n 1)"
out2=$("$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --include-active --dry-run)
assert_contains "F1: summary reports the real skipped count" "$out2" "[done ] sent=2 skipped=1"
