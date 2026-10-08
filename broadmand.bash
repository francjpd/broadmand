# broadmand.bash — bash entrypoint for broadmand.
# Sourced by broadmand.tmux under an explicit bash interpreter.
#
# Loads defaults and emits the keybindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=defaults.sh
. "$CURRENT_DIR/defaults.sh"

# shellcheck source=keybinds.sh
. "$CURRENT_DIR/keybinds.sh"
