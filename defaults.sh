# shellcheck shell=bash
# shellcheck disable=SC2034
# defaults.sh — broadmand configuration surface.
# This file defines every @-option name and its default value.
# Sourced by broadmand.bash and by worker scripts via util.sh.

# Sanity check: the multiplexer CLI must be available. Herdr sets
# HERDR_ENV=1 inside its panes and needs `herdr`; every other context is the
# tmux path and needs `tmux`.
if [ "${HERDR_ENV:-}" = "1" ]; then
  command -v herdr >/dev/null 2>&1 || {
    printf 'broadmand: herdr not found in PATH\n' >&2
    # shellcheck disable=SC2317  # exit is for the executed (not sourced) case.
    return 1 2>/dev/null || exit 1
  }
else
  command -v tmux >/dev/null 2>&1 || {
    printf 'broadmand: tmux not found in PATH\n' >&2
    # shellcheck disable=SC2317  # exit is for the executed (not sourced) case.
    return 1 2>/dev/null || exit 1
  }
fi

# Key bindings
BROADCAST_RUN_KEY_OPTION='@broadcast-run-key'
BROADCAST_RUN_KEY_DEFAULT='d'

BROADCAST_CD_PICKER_KEY_OPTION='@broadcast-cd-picker-key'
BROADCAST_CD_PICKER_KEY_DEFAULT='D'

# Directory picker backend
BROADCAST_PICKER_ENGINE_OPTION='@broadcast-picker-engine'
BROADCAST_PICKER_ENGINE_DEFAULT='fd'

# Commands whose panes should be skipped when broadcasting
BROADCAST_EXCLUDED_OPTION='@broadcast-excluded'
BROADCAST_EXCLUDED_DEFAULT='vim,vi,nvim,less,man,ssh,htop,top,mc,opencode,claude,aider,continue,qwen,qwen-cli,gemini,gemini-cli,openai,ollama,copilot,codeium,anthropic,chatgpt,chatgpt-cli,sgpt,aichat,pplx,perplexity'

# Milliseconds between tmux send-keys operations
BROADCAST_PANE_DELAY_OPTION='@broadcast-pane-delay'
BROADCAST_PANE_DELAY_DEFAULT='5'
