#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

get_all_sessions() {
  local current_session="$1"
  local save_dir="$(get_opt_dir)"
  local -A seen

  for file in "$save_dir"/*_last; do
    [[ -e "$file" ]] || continue
    local name="$(basename "${file%%_last}")"
    seen["$name"]="stored"
  done

  while IFS= read -r session; do
    seen["$session"]="loaded"
  done < <(tmux list-sessions -F "#{session_name}")

  for name in "${!seen[@]}"; do
    [[ "${seen[$name]}" == "loaded" ]] || continue
    if [[ "$name" == "$current_session" ]]; then
      printf "● %s (active)\n" "$name"
    else
      printf "● %s\n" "$name"
    fi
  done

  for name in "${!seen[@]}"; do
    [[ "${seen[$name]}" == "stored" ]] && printf "○ %s\n" "$name"
  done
}

pick() {
  local current_session="$(get_current_session_name)"
  local selected="$(get_all_sessions "$current_session" | fzf)"
  [[ -z "$selected" ]] && return 0

  local session_name
  session_name=${selected#● }
  session_name=${session_name#○ }
  session_name=${session_name% (active)}

  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux switch-client -t "$session_name"
  else
    exec "$CURRENT_DIR/restore.sh" "$session_name"
  fi
}

# TODO: unload session (save before killing)
# TODO: remove unload session
# TODO: rename session (rename old saves too to remove the duplicates)
# TODO: create new session
main() {
  case "${1:-}" in
  "") pick ;;
  esac
}
main
