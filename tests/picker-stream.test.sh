#!/usr/bin/env bash
# tests/picker-stream.test.sh — picker-stream behaviour with a fake engine.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

: "${BASH:=bash}"

BIN="$TMPDIR/picker-bin"
NOFD="$TMPDIR/picker-nofd"
FDFINDBIN="$TMPDIR/picker-fdfind"
mkdir -p "$BIN" "$NOFD" "$FDFINDBIN" "$HOME/sub"

# A tmux stub that reports the engine the test asks for.
cat > "$BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
if [ "${1:-}" = "show-options" ]; then
  name="${!#}"
  case "$name" in
    @broadcast-picker-engine) printf '%s\n' "${FAKE_ENGINE:-fd}" ;;
    @broadcast-excluded) printf '%s\n' "${FAKE_EXCLUDED:-}" ;;
    *) : ;;
  esac
fi
exit 0
TMUX
chmod +x "$BIN/tmux"

# A fake fd that records its arguments and emits a deterministic tree,
# including a duplicate to exercise the merge.
cat > "$BIN/fd" <<'FD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_FD_LOG:?}"
base=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--base-directory" ]; then base="$a"; fi
  prev="$a"
done
printf '%s\n' "$base"
printf '%s\n' "$base/sub"
printf '%s\n' "$base/sub/"
printf '%s\n' "$base"
FD
chmod +x "$BIN/fd"

# A fake zoxide.
cat > "$BIN/zoxide" <<'ZOX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_ZOXIDE_LOG:-/dev/null}"
printf '%s\n' "$HOME/zdir"
printf '%s\n' "$HOME/zdir/"
ZOX
chmod +x "$BIN/zoxide"

# Same stubs without fd, to simulate a missing engine.
cp "$BIN/tmux" "$NOFD/tmux"
cp "$BIN/tmux" "$FDFINDBIN/tmux"
cp "$BIN/fd" "$FDFINDBIN/fdfind"
chmod +x "$NOFD/tmux" "$FDFINDBIN/tmux" "$FDFINDBIN/fdfind"

# The merge step needs awk, the script needs dirname, and the stub scripts
# use `env bash`; expose all three in the stripped PATHs.
bash_path=$(command -v bash)
for d in "$BIN" "$NOFD" "$FDFINDBIN"; do
  ln -s "$(command -v awk)" "$d/awk"
  ln -s "$(command -v dirname)" "$d/dirname"
  ln -s "$bash_path" "$d/bash"
done

run_stream() {
  # run_stream <bin-dir> [args...] : sets STREAM_OUT, STREAM_ERR, STREAM_RC
  local bindir="$1"
  shift
  STREAM_RC=0
  STREAM_OUT=$(PATH="$bindir" FAKE_ENGINE="${FAKE_ENGINE:-fd}" \
    "$BASH" "$REPO_DIR/scripts/picker-stream.sh" "$@" 2>"$TMPDIR/stream.err") \
    || STREAM_RC=$?
  STREAM_ERR=$(cat "$TMPDIR/stream.err")
}

# --- missing engine fails loudly ---
FAKE_ENGINE=fd
run_stream "$NOFD"
assert_eq "missing engine exits non-zero" 1 "$STREAM_RC"
assert_contains "missing engine explains itself" "$STREAM_ERR" "not available"

# --- unknown engine fails loudly ---
FAKE_ENGINE=bogus
run_stream "$BIN"
assert_eq "unknown engine exits non-zero" 1 "$STREAM_RC"
assert_contains "unknown engine explains itself" "$STREAM_ERR" "unknown picker engine"

# --- fd stream, dedup and ordering ---
FAKE_ENGINE=fd
FAKE_FD_LOG="$TMPDIR/fd.log"
export FAKE_FD_LOG BROADCAST_FALLBACK_ROOT="$HOME"
rm -f "$FAKE_FD_LOG"
run_stream "$BIN"
expected=$(printf '%s\n%s' "$HOME" "$HOME/sub")
assert_eq "fd stream dedups and keeps cwd results first" "$expected" "$STREAM_OUT"
fd_args=$(cat "$FAKE_FD_LOG")
assert_contains "fd scan uses --type=d" "$fd_args" "--type=d"
assert_contains "fd scan excludes .git" "$fd_args" "--exclude .git"
assert_contains "fd scan caps depth at 3" "$fd_args" "--max-depth 3"

# --- fdfind fallback ---
FAKE_FD_LOG="$TMPDIR/fdfind.log"
rm -f "$FAKE_FD_LOG"
run_stream "$FDFINDBIN"
assert_eq "fdfind fallback yields the same stream" "$expected" "$STREAM_OUT"

# --- an existing directory query shows that directory ---
run_stream "$BIN" "sub/"
first_line=$(printf '%s\n' "$STREAM_OUT" | head -n 1)
assert_eq "relative query resolves against the fallback root" "$HOME/sub" "$first_line"

# --- tilde expansion ---
# shellcheck disable=SC2088  # the tilde must reach picker-stream unexpanded
run_stream "$BIN" '~/sub'
first_line=$(printf '%s\n' "$STREAM_OUT" | head -n 1)
assert_eq "tilde query expands to HOME" "$HOME/sub" "$first_line"

# --- zoxide engine ---
FAKE_ENGINE=zoxide
FAKE_ZOXIDE_LOG="$TMPDIR/zoxide.log"
export FAKE_ZOXIDE_LOG
rm -f "$FAKE_ZOXIDE_LOG"
run_stream "$BIN"
assert_contains "zoxide engine uses zoxide output" "$STREAM_OUT" "$HOME/zdir"
zoxide_args=$(cat "$FAKE_ZOXIDE_LOG")
assert_contains "zoxide is queried with -l" "$zoxide_args" "-l"
