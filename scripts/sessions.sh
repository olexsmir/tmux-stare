#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

declare S=$'\t'

# === common
get_current_session_name() {
  if [ "$(tmux display-message -p "#{session_grouped}")" = 0 ]; then
    tmux display-message -p "#{session_name}" 2>/dev/null || true
  else
    tmux display-message -p "#{session_group}" 2>/dev/null || true
  fi
}

rename_session() {
  local old="$1"
  local new="$2"
  local dir="$(get_opt_dir)"

  [[ -z "$new" || "$old" == "$new" ]] && return 1
  [[ -e "${dir}/${new}_last" ]] && return 1

  tmux has-session -t "$new" 2>/dev/null && return 1
  tmux rename-session -t "$old" "$new" 2>/dev/null

  local old_last="${dir}/${old}_last"
  [[ -L "$old_last" ]] && {
    local actual="$(readlink "$old_last")"
    local new_actual="${dir}/${new}_$(basename "$actual" | cut -d_ -f2-)"
    mv "$actual" "$new_actual"
    ln -sf "$new_actual" "${dir}/${new}_last"
    rm "$old_last"
  }
}

# === save
save_cwd() {
  local session_name="$1"
  local save_file="$2"
  tmux display-message -p -t "$session_name" -F "#{session_path}" >>"$save_file"
}

save_windows() {
  local session_name="$1"
  local save_file="$2"
  local format="window$S#{window_index}$S#{window_name}$S#{window_layout}$S#{window_active}"
  tmux list-windows -t "$session_name" -F "$format" >>"$save_file"

}

get_pane_child_pids() {
  local pane_pid="$1"
  ps -ao ppid=,pid= | awk -v pane_pid="$pane_pid" '$1 == pane_pid { print $2 }'
}

format_process_command() {
  local pid="$1"
  [[ -r "/proc/${pid}/cmdline" ]] || return 1
  xargs -0 bash -c 'printf "%q " "$0" "$@"' <"/proc/${pid}/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//'
}

build_command_from_pids() {
  local pids="$1"
  local pid
  local formatted
  local command=""
  for pid in $pids; do
    formatted="$(format_process_command "$pid")"
    [[ -z "$formatted" ]] && continue
    [[ -n "$command" ]] && command+=" | "
    command+="$formatted"
  done
  printf "%s" "$command"
}

collect_process_names() {
  local pids="$1"
  local pid
  local first_arg
  local name
  for pid in $pids; do
    [[ -r "/proc/${pid}/cmdline" ]] || continue
    first_arg="$(tr '\0' '\n' <"/proc/${pid}/cmdline" 2>/dev/null | head -n1)"
    [[ -z "$first_arg" ]] && continue
    name="$(basename "$first_arg")"
    [[ -n "$name" ]] && printf "%s\n" "$name"
  done | sort -u
}

strip_prompt_prefix() {
  local line="$1"
  if [[ "$line" =~ [\$\#\%\>][[:space:]]+.+$ ]]; then
    sed -E 's/^.*[#$%>][[:space:]]+//' <<<"$line"
  fi
}

find_command_from_pane_history() {
  local pane_target="$1"
  local process_names="$2"
  local line
  local candidate
  local name
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    candidate="$(strip_prompt_prefix "$line")"
    [[ -z "$candidate" ]] && continue
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if [[ "$candidate" == *"$name"* ]]; then
        printf "%s" "$candidate"
        return 0
      fi
    done <<<"$process_names"
  done < <(tmux capture-pane -pJ -S -200 -t "$pane_target" 2>/dev/null | tac)
}

save_panes() {
  local session_name="$1"
  local save_file="$2"
  local format="pane$S#{pane_index}$S#{pane_current_path}$S#{pane_active}$S#{window_index}$S#{pane_pid}"
  tmux list-panes -s -t "$session_name" -F "$format" |
    while IFS="$S" read -r line; do
      IFS="$S" read -r _ pane_index _ _ window_index pane_pid <<<"$line"
      pids="$(get_pane_child_pids "$pane_pid")"
      command="$(build_command_from_pids "$pids")"

      if [[ -n "$command" ]]; then
        process_names="$(collect_process_names "$pids")"
        pane_target="${session_name}:${window_index}.${pane_index}"
        pane_command="$(find_command_from_pane_history "$pane_target" "$process_names")"
        [[ -n "$pane_command" ]] && command="$pane_command"
      fi

      awk -v command="$command" \
        'BEGIN {FS=OFS="\t"} {$6=command; print}' \
        <<<"$line" >>"$save_file"
    done
}

link_session_last() {
  local save_file="$1"
  local last_file="$2"
  if ! cmp -s "$save_file" "$last_file"; then
    ln -sf "$save_file" "$last_file"
  else
    rm "$save_file"
  fi
}

link_last() {
  local save_file="$1"
  local save_dir="$2"
  ln -sf "$save_file" "$save_dir"/last
}

save_session() {
  local session_name="$1"
  local save_dir="$(get_opt_dir)"
  local save_file="${save_dir}/${session_name}_$(get_time)"
  local last_file="${save_dir}/${session_name}_last"

  save_cwd "$session_name" "$save_file"
  save_windows "$session_name" "$save_file"
  save_panes "$session_name" "$save_file"
  link_session_last "$save_file" "$last_file"
  link_last "$last_file" "$save_dir"
}

save_all_sessions() {
  tmux list-sessions -F "#{session_name}" | while read -r session; do
    save_session "$session"
  done

  local current_session="$(get_current_session_name)"
  if [[ -n "$current_session" ]]; then
    link_last "$(get_opt_dir)/${current_session}_last" "$(get_opt_dir)"
  fi
}

unload_session() {
  local session_name="$1"
  save_session "$session_name"
  tmux kill-session -t "$session_name"
}

# === restore
restore_pane_processes_enabled() {
  local processes="$(get_opt_processes)"
  [[ "$processes" != "false" ]]
}

restore_all_processes() {
  local processes="$(get_opt_processes)"
  [[ "$processes" == ":all:" ]]
}

restore_list() {
  get_opt_processes
}

get_proc_match_element() {
  local proc="$1"
  printf "%s" "${proc%%->*}"
}

proc_matches_command() {
  local command="$1"
  local match="$2"
  if [[ "${match:0:1}" == "~" ]]; then
    local relaxed="${match#~}"
    [[ "$command" == *"$relaxed"* ]]
  else
    [[ "$command" == "$match" || "$command" == "$match "* ]]
  fi
}

command_on_restore_list() {
  local command="$1"
  local proc
  local match
  local restore_list_value
  restore_list_value="$(restore_list)"
  # shellcheck disable=SC2086
  eval "set -- $restore_list_value"
  for proc in "$@"; do
    match="$(get_proc_match_element "$proc")"
    if proc_matches_command "$command" "$match"; then
      return 0
    fi
  done
  return 1
}

should_restore_command() {
  local command="$1"
  [[ -z "$command" ]] && return 1
  restore_pane_processes_enabled || return 1
  restore_all_processes && return 0
  command_on_restore_list "$command"
}

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
      if should_restore_command "$command"; then
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
  local session_name="$1"
  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux switch-client -t "$session_name"
    return 0
  fi

  local session_file="$(get_opt_dir)/${session_name}_last"
  if [[ ! -f "$session_file" ]]; then
    tmux display-message "No saved session found for: $session_name"
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
