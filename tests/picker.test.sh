#!/usr/bin/env bash
# tests/picker.test.sh — verifies the fzf preview command is portable.
# On BSD/macOS `ls --color` is an illegal option, so the preview used to be
# empty there (F6). This drives picker.sh with a fake fzf, reads back the
# exact --preview command, and runs it so the real OS `ls` is exercised.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap finish EXIT

: "${BASH:=bash}"

FAKE="$TMPDIR/picker-fake"
mkdir -p "$FAKE" "$TMPDIR/preview"
: > "$TMPDIR/preview/file.txt"

cat > "$FAKE/fzf" <<'FZF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_FZF_LOG:?}"
cat >/dev/null
exit 130
FZF
chmod +x "$FAKE/fzf"

cat > "$FAKE/fd" <<'FD'
#!/usr/bin/env bash
printf '%s\n' "$PWD"
FD
chmod +x "$FAKE/fd"

cat > "$FAKE/tmux" <<'TMUX'
#!/usr/bin/env bash
if [ "${1:-}" = "show-options" ]; then
  case "${!#}" in
    @broadcast-picker-engine) printf 'fd\n' ;;
    *) : ;;
  esac
fi
exit 0
TMUX
chmod +x "$FAKE/tmux"

export FAKE_FZF_LOG="$TMPDIR/fzf.log"
rm -f "$FAKE_FZF_LOG"
PATH="$FAKE:$PATH" "$BASH" "$REPO_DIR/scripts/picker.sh" "$TMPDIR/preview" \
  >/dev/null 2>&1 || true

if [ ! -s "$FAKE_FZF_LOG" ]; then
  _fail "picker.sh never reached fzf"
else
  preview=$(awk '/^--preview$/ { getline; print; exit }' "$FAKE_FZF_LOG")
  if [ -z "$preview" ]; then
    _fail "fzf was not given a --preview command"
  else
    preview_cmd=${preview//\{\}/$TMPDIR/preview}
    preview_out=$(sh -c "$preview_cmd" 2>/dev/null || true)
    assert_contains "preview lists files with this OS's ls (F6)" \
      "$preview_out" "file.txt"
  fi
fi
