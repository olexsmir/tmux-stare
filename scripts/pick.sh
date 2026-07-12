#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/sessions.sh"

get_all_sessions() {
  local current_session="$(get_current_session_name)"
  local save_dir="$(get_opt_dir)"
  local -A seen

  for file in "$save_dir"/*_last; do
    [[ -e "$file" ]] || continue
    local name="$(basename "${file%%_last}")"
    seen["$name"]="stored"
  done

  while IFS=' ' read -r session status_val; do
    [[ "$status_val" == "off" ]] && continue
    seen["$session"]="loaded"
  done < <(tmux list-sessions -F "#{session_name} #{status}")

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
  return 0
}

sanitize_session_name() {
  local name="$1"
  # trim leading/trailing whitespace
  read -r name <<< "$name"
  # replace chars that break tmux -t target parsing
  name="${name//./_}"
  name="${name//:/_}"
  echo "$name"
}

strip_session_name() {
  local name="${1#● }"
  name="${name#○ }"
  name="${name% (active)}"
  echo "$name"
}

pick() {
  local selected=$(get_all_sessions | fzf --reverse \
    --bind "ctrl-x:execute($0 unload {})+reload($0 list)" \
    --bind "ctrl-r:execute($0 rename {})+reload($0 list)" \
    --bind "ctrl-o:execute($0 new)+reload($0 list)" \
    --bind "enter:accept")

  [[ -z "$selected" ]] && return 0

  local session_name="$(strip_session_name "$selected")"
  local sid=$(get_session_id "$session_name")
  if [[ -n "$sid" ]]; then
    tmux switch-client -t "$sid"
  else
    restore_session "$session_name"
  fi
}

unload_or_kill() {
  local session_name="$(strip_session_name "$1")"
  local sid=$(get_session_id "$session_name")
  if [[ -n "$sid" ]]; then
    save_session "$session_name"
    tmux kill-session -t "$sid"
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
  local new_raw=$(printf "" | fzf --prompt="Rename ""$old_name"" to " --print-query)
  [[ -z "$new_raw" ]] && return 1
  local new_name="$(sanitize_session_name "$new_raw")"
  [[ -z "$new_name" ]] && return 1
  rename_session "$old_name" "$new_name"
}

new_session() {
  local raw_name=$(printf "" | fzf --prompt="New session name: " --print-query)
  [[ -z "$raw_name" ]] && return 1

  local name="$(sanitize_session_name "$raw_name")"
  [[ -z "$name" ]] && return 1

  local sid=$(get_session_id "$name")
  if [[ -n "$sid" ]]; then
    tmux switch-client -t "$sid"
  else
    local cwd="$(tmux display-message -p "#{pane_current_path}")"
    tmux new-session -ds "$name" -c "$cwd"
    # Use sid because $name may still contain chars that break -t
    sid=$(get_session_id "$name")
    if [[ -n "$sid" ]]; then
      tmux switch-client -t "$sid"
    fi
  fi
}

main() {
  case "${1:-}" in
  "") pick ;;
  unload) unload_or_kill "$2" ;;
  rename) rename "$2" ;;
  new) new_session ;;
  list) get_all_sessions ;;
  esac
}
main "$@"
