#!/usr/bin/env bash
# tests/herdr.test.sh — e2e for the Herdr broadcast path against a fake herdr.
#
# CI has no Herdr server, so the Herdr path is driven through a fake `herdr`
# on PATH (plus HERDR_ENV=1, the signal Herdr exports inside its panes). The
# fake records every pane send/run so the test can assert exactly which panes
# of the active workspace were targeted, and that excluded panes and other
# workspaces were left alone.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

: "${BASH:=bash}"
: "${PYTHON:=python3}"

BIN="$TMPDIR/herdr-bin"
mkdir -p "$BIN"

# A fake `herdr` that serves a fixed layout: workspace w1 has three panes
# (p1 active/bash, p2 vim/excluded, p3 bash) and workspace w2 has one pane
# that must never be targeted. It records send-keys/run calls into
# $FAKE_HERDR_LOG for the assertions below.
cat > "$BIN/herdr" <<'HERDR'
#!/usr/bin/env bash
LOG="${FAKE_HERDR_LOG:-/dev/null}"
cmd="${1:-}"
case "$cmd" in
  pane)
    sub="${2:-}"
    case "$sub" in
      current)
        if [ "${FAKE_HERDR_FAIL_CURRENT:-}" = "1" ]; then
          exit 1
        fi
        printf '%s\n' '{"id":"test","result":{"pane":{"pane_id":"w1:p1","workspace_id":"w1","cwd":"/home/user","foreground_cwd":"/home/user/project","focused":true},"type":"pane_current"}}'
        ;;
      list)
        if [ "${FAKE_HERDR_FAIL_LIST:-}" = "1" ]; then
          printf '%s\n' '{"id":"test","result":{"panes":[],"type":"pane_list"}}'
          exit 0
        fi
        case "${4:-}" in
          w1)
            printf '%s\n' '{"id":"test","result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1"},{"pane_id":"w1:p2","workspace_id":"w1"},{"pane_id":"w1:p3","workspace_id":"w1"}],"type":"pane_list"}}'
            ;;
          w2)
            printf '%s\n' '{"id":"test","result":{"panes":[{"pane_id":"w2:p1","workspace_id":"w2"}],"type":"pane_list"}}'
            ;;
          *)
            printf '%s\n' '{"id":"test","result":{"panes":[],"type":"pane_list"}}'
            ;;
        esac
        ;;
      process-info)
        case "${4:-}" in
          w1:p2)
            printf '{"id":"test","result":{"process_info":{"foreground_processes":[{"name":"sudo","pid":5379},{"name":"vim","pid":5541}],"foreground_process_group_id":5541,"pane_id":"w1:p2"},"type":"pane_process_info"}}\n'
            ;;
          *)
            printf '{"id":"test","result":{"process_info":{"foreground_processes":[{"name":"sudo","pid":5379},{"name":"bash","pid":5541}],"foreground_process_group_id":5541,"pane_id":"%s"},"type":"pane_process_info"}}\n' "${4:-}"
            ;;
        esac
        ;;
      send-keys)
        printf 'send-keys %s %s\n' "${3:-}" "${4:-}" >> "$LOG"
        ;;
      run)
        printf 'run %s %s\n' "${3:-}" "${4:-}" >> "$LOG"
        ;;
      *)
        printf '%s\n' "unknown pane subcommand: $sub" >&2
        exit 2
        ;;
    esac
    ;;
  notification)
    printf 'notify %s\n' "${3:-}" >> "$LOG"
    ;;
  *)
    printf '%s\n' "unknown command: $cmd" >&2
    exit 2
    ;;
esac
HERDR
chmod +x "$BIN/herdr"

export FAKE_HERDR_LOG="$TMPDIR/herdr.log"
export HERDR_ENV=1
export PATH="$BIN:$PATH"

# --- the foreground command is the process-group leader, not the lowest pid ---
got_cmd=$("$BASH" -c '. "$1/scripts/util.sh"; pane_command w1:p2' -- "$REPO_DIR")
assert_eq "herdr pane command is the foreground process group leader" "vim" "$got_cmd"
assert_not_contains "herdr pane command ignores the lower-pid wrapper" "$got_cmd" "sudo"

# --- dry-run: enumerate the active workspace, skip excluded and active ---
out=$("$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --include-active --dry-run)
assert_contains "herdr dry-run includes the active pane" "$out" "[send ] pane=w1:p1"
assert_contains "herdr dry-run skips the excluded vim pane" "$out" "[skip ] pane=w1:p2 reason=excluded(vim)"
assert_contains "herdr dry-run sends to the other eligible pane" "$out" "[send ] pane=w1:p3"
assert_contains "herdr dry-run summary counts sends and skips" "$out" "[done ] sent=2 skipped=1"
assert_not_contains "herdr dry-run never touches another workspace" "$out" "w2:p1"

# --- dry-run without --include-active: the active pane is skipped ---
out2=$("$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --dry-run)
assert_contains "herdr skips the active pane by default" "$out2" "[skip ] pane=w1:p1 reason=active-pane"
assert_contains "herdr summary without --include-active" "$out2" "[done ] sent=1 skipped=2"

# --- real run: only the eligible panes of the active workspace are sent to ---
rm -f "$FAKE_HERDR_LOG"
"$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --include-active
log=$(cat "$FAKE_HERDR_LOG" 2>/dev/null || true)
assert_contains "herdr sends to the active pane" "$log" "run w1:p1 echo hi"
assert_contains "herdr sends to the other eligible pane" "$log" "run w1:p3 echo hi"
assert_not_contains "herdr does not send to the excluded pane" "$log" "w1:p2"
assert_not_contains "herdr does not send to another workspace" "$log" "w2:p1"

# --- literal delivery: the command reaches the pane byte-for-byte ---
# shellcheck disable=SC2016  # the literal dollars/quotes are the point of the test
tricky='literal: a b;c "d" $e `f` --g'
rm -f "$FAKE_HERDR_LOG"
"$BASH" "$REPO_DIR/scripts/broadcast.sh" "$tricky" --include-active
log2=$(cat "$FAKE_HERDR_LOG" 2>/dev/null || true)
assert_contains "herdr delivers the command literally" "$log2" "$tricky"

# --- an unresolvable active workspace fails loudly, broadcasting nothing ---
FAKE_HERDR_FAIL_CURRENT=1
export FAKE_HERDR_FAIL_CURRENT
if ("$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --include-active --dry-run) \
    >"$TMPDIR/herdr-fail.out" 2>"$TMPDIR/herdr-fail.err"; then
  _fail "herdr broadcast fails when the active workspace is unresolvable"
else
  _pass "herdr broadcast fails when the active workspace is unresolvable"
fi
assert_contains "unresolvable workspace explains itself" \
  "$(cat "$TMPDIR/herdr-fail.err" 2>/dev/null || true)" \
  "could not resolve the active Herdr"
unset FAKE_HERDR_FAIL_CURRENT

# --- an empty pane list fails loudly rather than reporting sent=0 skipped=0 ---
FAKE_HERDR_FAIL_LIST=1
export FAKE_HERDR_FAIL_LIST
if ("$BASH" "$REPO_DIR/scripts/broadcast.sh" 'echo hi' --include-active --dry-run) \
    >"$TMPDIR/herdr-list-fail.out" 2>"$TMPDIR/herdr-list-fail.err"; then
  _fail "herdr broadcast fails when the pane list is empty"
else
  _pass "herdr broadcast fails when the pane list is empty"
fi
assert_contains "empty pane list explains itself" \
  "$(cat "$TMPDIR/herdr-list-fail.err" 2>/dev/null || true)" \
  "could not list the panes"
assert_not_contains "empty pane list reports no phantom success" \
  "$(cat "$TMPDIR/herdr-list-fail.out" 2>/dev/null || true)" \
  "sent=0 skipped=0"
unset FAKE_HERDR_FAIL_LIST

# --- the modal cd picker works under Herdr and broadcasts `cd <dir>` ---
cat > "$BIN/fzf" <<'FZF'
#!/usr/bin/env bash
cat >/dev/null
printf '/home/user/project/subdir\n'
FZF
chmod +x "$BIN/fzf"

cat > "$BIN/fd" <<'FD'
#!/usr/bin/env bash
printf '%s\n' '/home/user/project'
FD
chmod +x "$BIN/fd"

rm -f "$FAKE_HERDR_LOG"
"$BASH" "$REPO_DIR/scripts/cd-all.sh" picker
log3=$(cat "$FAKE_HERDR_LOG" 2>/dev/null || true)
assert_contains "herdr cd picker broadcasts builtin cd" "$log3" \
  "builtin cd '/home/user/project/subdir'"

# --- the free-form broadcaster (run-all.sh) works under Herdr ---
# run-all.sh runs popup.sh inline in the pane, which needs a pty; drive it the
# same way popup.test.sh drives the popup primitive.
if command -v "$PYTHON" >/dev/null 2>&1; then
  rm -f "$FAKE_HERDR_LOG"
  b64=$(printf 'echo hi\r' | base64 | tr -d '\n')
  "$PYTHON" "$TESTS_DIR/ptydrive.py" --timeout 15 --input "$b64" -- \
    "$BASH" "$REPO_DIR/scripts/run-all.sh" >/dev/null 2>&1
  log4=$(cat "$FAKE_HERDR_LOG" 2>/dev/null || true)
  assert_contains "herdr run-all broadcasts the typed command" "$log4" "run w1:p1 echo hi"
  assert_contains "herdr run-all sends to all eligible panes" "$log4" "run w1:p3 echo hi"
  assert_not_contains "herdr run-all does not send to the excluded pane" "$log4" "w1:p2"
else
  printf '  note %s not found; skipping herdr run-all pty test\n' "$PYTHON"
  _pass "herdr run-all test skipped (no python3)"
fi
