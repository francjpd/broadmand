#!/usr/bin/env bash
# tests/integration.test.sh — headless-tmux integration tests.
# Loads the plugin the way TPM/manual installs do, asserts the prefix
# bindings, and broadcasts into a window with eligible, excluded, and
# copy-mode panes.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=../scripts/util.sh
. "$REPO_DIR/scripts/util.sh"

: "${BASH:=bash}"

tmux_start
cleanup() {
  local rc=$?
  tmux_stop
  finish "$rc"
}
trap cleanup EXIT

# --- plugin loads and registers the expected prefix bindings ---
# TPM runs each *.tmux file as an executable, which is what this is.
"$REPO_DIR/broadmand.tmux"
keys=$(tmux list-keys -T prefix | tr -s ' ')
assert_contains "run-all binding is registered" "$keys" "run-all.sh"
assert_contains "cd-all binding is registered" "$keys" "cd-all.sh"
assert_contains "prefix d is bound" "$keys" "-T prefix d run-shell"
assert_contains "prefix D is bound" "$keys" "-T prefix D run-shell"

# Manual install uses `run-shell <entrypoint>`; tmux runs it with /bin/sh,
# so this only works if the bash shebang is honoured.
if tmux run-shell "$REPO_DIR/broadmand.tmux" >/dev/null 2>&1; then
  _pass "manual run-shell install path loads the plugin"
else
  _fail "manual run-shell install path failed"
fi

# --- broadcast skip logic ---
win_name="bmtest"
tmux new-window -d -n "$win_name" "$BASH"
win=$(tmux list-windows -F '#{window_id} #{window_name}' \
  | awk -v name="$win_name" '$2 == name { print $1 }')
if [ -z "$win" ]; then
  _fail "could not create the broadcast test window"
  exit 0
fi

p1=$(tmux list-panes -t "$win" -F '#{pane_id}' | head -n 1)
tmux split-window -t "$win" "exec sleep 300"
p2=$(tmux list-panes -t "$win" -F '#{pane_id}' | tail -n 1)
tmux split-window -t "$win" "$BASH"
p3=$(tmux list-panes -t "$win" -F '#{pane_id}' | tail -n 1)
tmux copy-mode -t "$p3"
tmux select-window -t "$win"
tmux select-pane -t "$p1"
tmux set-option -g @broadcast-excluded 'sleep'
# Let the freshly spawned eligible shell finish initialising.
sleep 1

marker="$TMPDIR/marker.log"
rm -f "$marker"
marker_line="printf '%s\\n' \"\$TMUX_PANE\" >> '$marker'"
"$BASH" "$REPO_DIR/scripts/broadcast.sh" "$marker_line" --include-active

for ((i = 0; i < 50; i++)); do
  [ -s "$marker" ] && break
  sleep 0.1
done
marker_text=$(cat "$marker" 2>/dev/null || true)
assert_contains "eligible active pane received the broadcast" "$marker_text" "$p1"
assert_not_contains "excluded pane was skipped" "$marker_text" "$p2"
assert_not_contains "copy-mode pane was skipped" "$marker_text" "$p3"

# --- F4: input is delivered literally (no tmux key interpretation) ---
f4_file="$TMPDIR/f4.txt"
rm -f "$f4_file"
# shellcheck disable=SC2016  # the literal dollars are the point of the test
tricky='literal: a b;c "d" $e `f` --g'
f4_line="printf '%s\\n' $(shell_quote "$tricky") > $(shell_quote "$f4_file")"
"$BASH" "$REPO_DIR/scripts/broadcast.sh" "$f4_line" --include-active
for ((i = 0; i < 50; i++)); do
  [ -s "$f4_file" ] && break
  sleep 0.1
done
assert_eq "broadcast delivers shell input literally" "$tricky" \
  "$(cat "$f4_file" 2>/dev/null || true)"
