#!/usr/bin/env bash
# scripts/picker.sh — choose a directory using fzf. Part of broadmand.
#
# Usage:
#   picker.sh [active_cwd]
#
# Loads the directory list via picker-stream.sh. On open the stream
# combines the active pane's cwd with $HOME. As soon as the user types,
# picker-stream.sh is re-run with the typed text as the new root path.
#
# Returns 0 with empty stdout if user cancels (Esc in fzf).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=util.sh
. "$SCRIPT_DIR/util.sh"

# Fail early with a friendly message instead of opening an empty picker.
require_picker_engine

# Where fd should start from for the fallback initial load.
# Passed as $1 from cd-all.sh (the active pane's cwd).
_fd_root="${1:-$HOME}"

# Export the fallback root so picker-stream.sh can read it.
export BROADCAST_FALLBACK_ROOT="$_fd_root"

run_fzf() {
  # Portable preview: BSD/macOS ls has no --color, so keep it plain. Using
  # -G on Darwin and --color on GNU would work but plain ls is simplest and
  # never fails with "illegal option".
  fzf --prompt="dir> " \
      --height=100% \
      --reverse \
      --no-multi \
      --bind "change:reload(bash '$SCRIPT_DIR/picker-stream.sh' \"{q}\" 2>/dev/null || true)" \
      --preview 'ls -la "{}" 2>/dev/null | head -50'
}

# Initial load: picker-stream.sh with empty query, piped into fzf.
chosen=$(bash "$SCRIPT_DIR/picker-stream.sh" 2>/dev/null | run_fzf) || exit 0

[ -z "${chosen:-}" ] && exit 0
printf '%s\n' "$chosen"
