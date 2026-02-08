#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# TODO: set the separator globally, or do whole sessions in one module
declare S=$'\t'

restore_session_from_file() {
  local session_file="$1"
  local session_name=$(basename "$session_file" | sed 's/_last$//')
  exec <"$session_file"

  start_spinner "Restoring session $session_name"

  local session_path="$(head -n1 | cut -d"$SEPARATOR" -f2)"
  tmux new-session -ds "$session_name" -c "$session_path"

  declare -A window_layouts
  declare active_window
  while read -r line; do
    case $line in
    window*)
      IFS=$S read -r _ window_index window_name window_layout window_active <<<"$line"
      window_id="$session_name:$window_index"
      tmux new-window -k -t "$window_id" -n "$window_name"
      window_layouts["$window_id"]="$window_layout"
      if [[ "$window_active" == "1" ]]; then
        active_window="$window_id"
      fi
      ;;

    pane*)
      IFS=$S read -r _ pane_index pane_current_path pane_active window_index command <<<"$line"
      if [[ "$pane_index" == "$(get_tmux_option base-index 0)" ]]; then
        tmux send-keys -t "$session_name:$window_index" "cd \"$pane_current_path\"" Enter "clear" Enter
      else
        tmux split-window -d -t "$session_name:$window_index" -c "$pane_current_path"
      fi
      if [[ "$pane_active" == "1" ]]; then
        tmux select-pane -t "$session_name:$window_index.$pane_index"
      fi
      if [[ -n "$command" ]]; then
        tmux send-keys -t "$session_name:$window_index.$pane_index" "$command" Enter
      fi
      ;;
    esac
  done

  for window in "${!window_layouts[@]}"; do
    tmux select-layout -t "$window" "${window_layouts[$window]}"
  done

  tmux select-window -t "$active_window"
  tmux switch-client -t "$session_name"
  stop_spinner "Session restored"
}

restore_session() {
  local name="$1"
  if tmux has-session -t "$name" 2>/dev/null; then
    tmux switch-client -t "$name"
    return 0
  fi

  local session_file="$(get_opt_dir)/${name}_last"
  if [[ ! -f "$session_file" ]]; then
    tmux display-message "No saved session found for: $name"
    return 1
  fi

  restore_session_from_file "$session_file"
}

restore_last() {
  local last_file="$(get_opt_dir)/last"
  if [[ ! -e "$last_file" ]]; then
    tmux display-message "No last session saved"
    return 1
  fi

  local session_name=$(basename "$(readlink "$last_file")" | sed 's/_last$//')
  restore_session "$session_name"
}

main() {
  if [[ -n "$1" ]]; then
    restore_session "$1"
  else
    restore_last
  fi
}
main "$@"
