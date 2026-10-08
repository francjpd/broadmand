#!/usr/bin/env bash
# broadmand — entrypoint loaded from the user's tmux.conf.
#
# TPM install:
#   set -g @plugin 'francjpd/broadmand'
#   run '~/.tmux/plugins/tpm/tpm'
#
# Manual install:
#   run-shell "~/.tmux/plugins/broadmand/broadmand.tmux"
#
# tmux run-shell executes commands with /bin/sh (dash on Debian/Ubuntu) and
# TPM runs each *.tmux file as an executable. The bash shebang above makes
# both paths run this file under bash, so the bash-only entrypoint below can
# be sourced without a manual re-exec.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=broadmand.bash
. "$CURRENT_DIR/broadmand.bash"
