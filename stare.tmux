#!/usr/bin/env bash
set -x

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

main() {
  local pick_key="$(get_opt_pick)"
  [[ -n "$pick_key" ]] && tmux bind-key "$pick_key" run-shell "tmux display-popup -E -w 25% -h 30% '$CURRENT_DIR/scripts/pick.sh'"

  local save_key="$(get_opt_save)"
  [[ -n "$save_key" ]] && tmux bind-key "$save_key" run-shell "$CURRENT_DIR/scripts/save.sh"
}
main
