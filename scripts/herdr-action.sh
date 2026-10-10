#!/usr/bin/env bash
# scripts/herdr-action.sh — open a broadmand popup pane from a plugin action.
#
# Herdr plugin actions run detached without a terminal, so they cannot host
# broadmand's interactive broadcaster or picker directly. This opens the
# matching popup pane entrypoint (which has a terminal) instead, so a
# `plugin_action` keybinding opens the popup exactly like the plugin UI or
# `herdr plugin pane open` does.
set -euo pipefail

entrypoint="${1:?usage: herdr-action.sh <entrypoint-id>}"

"${HERDR_BIN_PATH:-herdr}" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-broadmand}" \
  --entrypoint "$entrypoint"
