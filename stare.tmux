#!/usr/bin/env bash
set -x

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

add_save_interpolation() {
  local status_right_value="$(get_tmux_option "status-right" "")"
  local save_interpolation="#($CURRENT_DIR/scripts/_auto_save.sh)"

  if [[ "$status_right_value" != *"$save_interpolation"* ]]; then
    set_tmux_option "status-right" "${save_interpolation}${status_right_value}"
  fi
}

main() {
  local pick_key="$(get_opt_pick)"
  [[ -n "$pick_key" ]] && tmux bind-key "$pick_key" run-shell "bash \"$CURRENT_DIR/scripts/_pick.sh\""

  local save_key="$(get_opt_save)"
  [[ -n "$save_key" ]] && tmux bind-key "$save_key" run-shell "bash \"$CURRENT_DIR/scripts/_save.sh\""

  local start_action="$(get_opt_start)"
  if [[ "$(get_opt_initialized)" == "0" ]]; then
    if [[ "$start_action" == "last" ]]; then
      tmux run-shell -b "sleep 0.1 && bash \"$CURRENT_DIR/scripts/_restore.sh\""
    elif [[ "$start_action" == "pick" ]]; then
      tmux run-shell -b "sleep 0.1 && bash \"$CURRENT_DIR/scripts/_pick.sh\""
    fi

    set_opt_initialized "1"
  fi

  # rename hook
  tmux set-hook -g session-renamed "run-shell \"bash '$CURRENT_DIR/scripts/_session_renamed.sh' #{q:hook_session} #{q:hook_session_name}\""
  tmux run-shell "bash '$CURRENT_DIR/scripts/_session_renamed.sh' sync"

  add_save_interpolation
}
main
