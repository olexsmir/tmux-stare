#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/sessions.sh"

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

strip_session_name() {
  local name="${1#● }"
  name="${name#○ }"
  name="${name% (active)}"
  echo "$name"
}

pick() {
  local selected=$(get_all_sessions "$(get_current_session_name)" | fzf \
    --footer="C-x: unload/kill | C-r: rename | C-n: new" \
    --bind "ctrl-x:execute($0 unload {})+reload($0 list)" \
    --bind "ctrl-r:execute($0 rename {})+reload($0 list)" \
    --bind "ctrl-n:execute($0 new)+reload($0 list)" \
    --bind "enter:accept")

  [[ -z "$selected" ]] && return 0

  local session_name="$(strip_session_name "$selected")"
  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux switch-client -t "$session_name"
  else
    restore_session "$session_name"
  fi
}

unload_or_kill() {
  local session_name="$(strip_session_name "$1")"
  if tmux has-session -t "$session_name" 2>/dev/null; then
    save_session "$session_name"
    tmux kill-session -t "$session_name"
  else
    confirm_delete "$session_name"
  fi
}

confirm_delete() {
  local session_name="$1"
  local save_dir="$(get_opt_dir)"
  local session_file="$save_dir/${session_name}_last"

  local result
  result=$(printf "Delete\nCancel" | fzf --header="Delete saved session '$session_name'?")
  if [[ "$result" == "Delete" ]]; then
    rm -f "$session_file"
  fi
}

rename() {
  local old_name="$(strip_session_name "$1")"
  local new_name=$(printf "" | fzf --prompt="Rename ""$old_name"" to " --print-query)
  [[ -z "$new_name" ]] && return 1
  rename_session "$old_name" "$new_name"
}

new_session() {
  local name=$(printf "" | fzf --prompt="New session name: " --print-query)
  [[ -z "$name" ]] && return 1

  if tmux has-session -t "$name" 2>/dev/null; then
    tmux switch-client -t "$name"
  else
    local cwd="$(tmux display-message -p "#{pane_current_path}")"
    tmux new-session -ds "$name" -c "$cwd"
    tmux switch-client -t "$name"
  fi
}

main() {
  case "${1:-}" in
  "") pick ;;
  unload) unload_or_kill "$2" ;;
  rename) rename "$2" ;;
  new) new_session ;;
  list) get_all_sessions "$(get_current_session_name)" ;;
  esac
}
main "$@"
