#!/usr/bin/env bash
# scripts/util.sh — shared helpers for broadmand
# Source this from sibling scripts. Not executable on its own.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../defaults.sh
. "$SCRIPT_DIR/../defaults.sh"

# Which multiplexer is driving this session: "tmux" or "herdr".
# Herdr exports HERDR_ENV=1 inside its managed panes; every other context is
# the tmux path broadmand has always supported.
broadcast_multiplexer() {
  if [ "${HERDR_ENV:-}" = "1" ]; then
    printf 'herdr\n'
  else
    printf 'tmux\n'
  fi
}

# Print an error to the multiplexer status surface and exit non-zero. Under
# tmux run-shell discards stderr, so the message is also shown via
# display-message; under herdr stderr is already visible in the pane.
die() {
  local msg="$1"
  case "$(broadcast_multiplexer)" in
    herdr) herdr notification show "broadmand: $msg" 2>/dev/null || true ;;
    tmux)  tmux display-message "broadmand: $msg" 2>/dev/null || true ;;
  esac
  printf 'broadmand: %s\n' "$msg" >&2
  exit 1
}

# Show a non-error status message the way the tmux path flashes the status
# line. Under herdr this becomes a toast, under tmux a status line.
broadcast_status() {
  local msg="$1"
  case "$(broadcast_multiplexer)" in
    herdr) herdr notification show "$msg" 2>/dev/null || true ;;
    tmux)  tmux display-message "$msg" 2>/dev/null || true ;;
  esac
}

# Extract every string value for `"<key>":"value"` from herdr's JSON reply on
# stdin, one per line. The fields broadmand reads (pane/workspace ids, cwd,
# process names) are plain strings with no embedded quotes or escapes, so a
# targeted match keeps the scripts free of a JSON parser dependency.
herdr_json_field() {
  local key="$1"
  awk -v key="$key" '
    {
      line = $0
      pat = "\"" key "\":\""
      for (;;) {
        i = index(line, pat)
        if (i == 0) break
        line = substr(line, i + length(pat))
        j = index(line, "\"")
        if (j == 0) break
        print substr(line, 1, j - 1)
        line = substr(line, j + 1)
      }
    }
  '
}

# Read a tmux @-option from global scope, fall back to default. Herdr has no
# @-option surface, so its configuration values fall back to the defaults.
tmux_opt() {
  local name="$1" default="$2"
  local val
  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    printf '%s' "${default}"
    return
  fi
  val=$(tmux show-options -gqv "$name" 2>/dev/null) || val=""
  printf '%s' "${val:-$default}"
}

# Option accessors using the centralized defaults from defaults.sh.
broadcast_run_key() {
  tmux_opt "$BROADCAST_RUN_KEY_OPTION" "$BROADCAST_RUN_KEY_DEFAULT"
}

broadcast_cd_picker_key() {
  tmux_opt "$BROADCAST_CD_PICKER_KEY_OPTION" "$BROADCAST_CD_PICKER_KEY_DEFAULT"
}

broadcast_picker_engine() {
  tmux_opt "$BROADCAST_PICKER_ENGINE_OPTION" "$BROADCAST_PICKER_ENGINE_DEFAULT"
}

broadcast_excluded() {
  tmux_opt "$BROADCAST_EXCLUDED_OPTION" "$BROADCAST_EXCLUDED_DEFAULT"
}

broadcast_pane_delay() {
  tmux_opt "$BROADCAST_PANE_DELAY_OPTION" "$BROADCAST_PANE_DELAY_DEFAULT"
}

# Get all pane IDs in the active window (tmux) or active workspace (herdr),
# one per line.
active_pane_ids() {
  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    herdr_active_pane_ids
    return
  fi
  local wid
  wid=$(tmux display-message -p '#{window_id}')
  tmux list-panes -t "$wid" -F '#{pane_id}'
}

# Resolve the active Herdr workspace id from the calling pane. Fails (empty
# output, non-zero) when it cannot be determined, so callers never broadcast
# to an ambiguous set of panes.
herdr_active_workspace_id() {
  local json wid
  json=$(herdr pane current --current 2>/dev/null) || return 1
  wid=$(printf '%s\n' "$json" | herdr_json_field workspace_id | head -n 1)
  [ -n "$wid" ] || return 1
  printf '%s\n' "$wid"
}

# All pane IDs in the active Herdr workspace, one per line.
herdr_active_pane_ids() {
  local wid
  wid=$(herdr_active_workspace_id) \
    || die "could not resolve the active Herdr workspace"
  herdr pane list --workspace "$wid" 2>/dev/null | herdr_json_field pane_id
}

# Get the active pane id.
active_pane_id() {
  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    herdr_active_pane_id
  else
    tmux display-message -p '#{pane_id}'
  fi
}

# The focused Herdr pane id, failing loudly when it cannot be resolved. This
# runs in the parent shell (not the broadcast process substitution) so the
# failure is fatal to broadcast.sh instead of silently producing an empty
# pane list.
herdr_active_pane_id() {
  local json pid
  json=$(herdr pane current --current 2>/dev/null) \
    || die "could not resolve the active Herdr pane"
  pid=$(printf '%s\n' "$json" | herdr_json_field pane_id | head -n 1)
  [ -n "$pid" ] || die "could not resolve the active Herdr pane"
  printf '%s\n' "$pid"
}

# Working directory of the active pane, used to seed the popup and picker.
active_pane_cwd() {
  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    herdr_active_pane_cwd
  else
    tmux display-message -p '#{pane_current_path}'
  fi
}

# cwd of the calling Herdr pane. Prefer foreground_cwd (the cwd of the pane's
# foreground process, the closest analog of tmux's pane_current_path) and fall
# back to the pane cwd when it is unavailable.
herdr_active_pane_cwd() {
  local json cwd
  json=$(herdr pane current --current 2>/dev/null) || { printf '%s\n' "$HOME"; return 0; }
  cwd=$(printf '%s\n' "$json" | herdr_json_field foreground_cwd | head -n 1)
  [ -n "$cwd" ] || cwd=$(printf '%s\n' "$json" | herdr_json_field cwd | head -n 1)
  printf '%s\n' "${cwd:-$HOME}"
}

# Get the working command of a pane (e.g. "zsh", "vim").
pane_command() {
  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    herdr_pane_command "$1"
  else
    tmux display-message -p -t "$1" '#{pane_current_command}' 2>/dev/null
  fi
}

# Foreground process name of a Herdr pane, the analog of tmux's
# pane_current_command. process-info reports the foreground process group; its
# first entry is the command running in the foreground (the shell itself when
# the pane is at a prompt).
herdr_pane_command() {
  local json
  json=$(herdr pane process-info --pane "$1" 2>/dev/null) || { printf ''; return 0; }
  printf '%s\n' "$json" | herdr_json_field name | head -n 1
}

# Is the pane currently in any tmux mode (copy mode, etc.)? Echoes yes/no.
# #{pane_in_mode} is a count: panes can have stacked modes, so any non-zero
# value means the pane is busy and must be skipped. An empty reply (query
# failed) counts as "no".
pane_in_mode() {
  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    # Herdr has no copy-mode equivalent; a busy pane is instead caught by the
    # foreground-command exclusion above.
    echo no
    return
  fi
  local in
  in=$(tmux display-message -p -t "$1" '#{pane_in_mode}' 2>/dev/null) || in=""
  if [ -n "$in" ] && [ "$in" != "0" ]; then
    echo yes
  else
    echo no
  fi
}

# Is the pane's command in the excluded list? Echoes yes/no.
# Entries are comma-separated; surrounding whitespace is trimmed.
pane_excluded() {
  local pane_id="$1" excluded="$2"
  local cmd x
  cmd=$(pane_command "$pane_id")
  if [ -z "$cmd" ]; then
    echo yes
    return
  fi

  local IFS=','
  for x in $excluded; do
    x="${x#"${x%%[![:space:]]*}"}"   # trim leading whitespace
    x="${x%"${x##*[![:space:]]}"}"  # trim trailing whitespace
    if [ "$x" = "$cmd" ] || [ "$x" = "${cmd%%.*}" ]; then
      echo yes
      return
    fi
  done
  echo no
}

# Quote a string using single-quote escaping.
# Each embedded single-quote is replaced with '\''  (end literal, add quote, resume literal).
# The whole string is wrapped in single quotes so the shell preserves spaces/special chars.
# This is compatible with zoxide, zsh, and bash.
shell_quote() {
  local s="$1"
  # Escape embedded single quotes: '  →  '\''
  s=${s//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

# Return the number of seconds to sleep for the configured pane delay.
__pane_delay_seconds() {
  local delay_ms="${PANE_DELAY_MS:-5}"
  if [[ "$delay_ms" =~ ^[0-9]+$ ]] && [ "$delay_ms" -gt 0 ]; then
    awk "BEGIN{print $delay_ms/1000}"
  else
    printf '0\n'
  fi
}

# Send a literal line to a pane, clearing any half-typed input first.
# Honors PANE_DELAY_MS between operations.
send_to_pane() {
  local pane_id="$1" line="$2"
  local delay_sec
  delay_sec=$(__pane_delay_seconds)

  if [ "$(broadcast_multiplexer)" = "herdr" ]; then
    # Clear any half-typed input, then submit the line + Enter atomically.
    herdr pane send-keys "$pane_id" ctrl+u
    [ "$delay_sec" != "0" ] && sleep "$delay_sec"
    herdr pane run "$pane_id" "$line"
    [ "$delay_sec" != "0" ] && sleep "$delay_sec"
    return
  fi

  tmux send-keys -t "$pane_id" C-u
  [ "$delay_sec" != "0" ] && sleep "$delay_sec"
  tmux send-keys -t "$pane_id" -l -- "$line"
  [ "$delay_sec" != "0" ] && sleep "$delay_sec"
  tmux send-keys -t "$pane_id" Enter
  [ "$delay_sec" != "0" ] && sleep "$delay_sec"
}

# Find the fd executable. On Debian/Ubuntu it may be installed as fdfind.
find_fd() {
  if command -v fd >/dev/null 2>&1; then
    printf '%s\n' "fd"
  elif command -v fdfind >/dev/null 2>&1; then
    printf '%s\n' "fdfind"
  else
    printf '%s\n' ""
  fi
}

# Normalize a user-typed path: expand a leading ~, resolve relative paths
# against $2 (the active pane's cwd, default $HOME), and strip trailing
# slashes (except for /). Echoes the normalized path (empty input -> empty).
normalize_path() {
  local p="${1:-}" root="${2:-$HOME}"
  [ -z "$p" ] && return 0
  p="${p/#\~/$HOME}"
  case "$p" in
    /*) ;;
    *)  p="$root/$p" ;;
  esac
  while [ "$p" != "${p%/}" ] && [ "$p" != "/" ]; do
    p="${p%/}"
  done
  printf '%s' "$p"
}

# Is the configured picker engine runnable? Echoes yes/no.
# fd needs fd/fdfind; zoxide falls back to fd; both needs at least one.
# Unknown engine names are reported as unavailable.
picker_engine_available() {
  local engine="$1" have_fd=no have_zoxide=no
  [ -n "$(find_fd)" ] && have_fd=yes
  command -v zoxide >/dev/null 2>&1 && have_zoxide=yes
  case "$engine" in
    fd)
      if [ "$have_fd" = yes ]; then echo yes; else echo no; fi
      ;;
    zoxide|both)
      if [ "$have_zoxide" = yes ] || [ "$have_fd" = yes ]; then echo yes; else echo no; fi
      ;;
    *)
      echo no
      ;;
  esac
}

# Fail with a friendly message when the configured picker engine is missing,
# instead of launching an empty picker.
require_picker_engine() {
  local engine
  engine=$(broadcast_picker_engine)
  if [ "$(picker_engine_available "$engine")" = yes ]; then
    return 0
  fi
  case "$engine" in
    fd)     die "fd not found; install fd or set @broadcast-picker-engine to zoxide" ;;
    zoxide) die "zoxide not found; install zoxide or fd, or change @broadcast-picker-engine" ;;
    both)   die "neither zoxide nor fd found; install one or change @broadcast-picker-engine" ;;
    *)      die "unknown @broadcast-picker-engine '$engine' (expected fd, zoxide, or both)" ;;
  esac
}
