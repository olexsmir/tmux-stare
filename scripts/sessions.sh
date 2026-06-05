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

  [[ -z "$old" || -z "$new" || "$old" == "$new" ]] && return 1
  [[ -e "$(get_opt_dir)/${new}_last" ]] && return 1

  tmux has-session -t "$new" 2>/dev/null && return 1
  tmux rename-session -t "$old" "$new" 2>/dev/null

  local old_last="${dir}/${old}_last"
  [[ -L "$old_last" ]] && {
    local actual="$(readlink "$old_last")"
    local actual_basename="$(basename "$actual")"
    local timestamp="${actual_basename: -15}"
    local new_actual="${dir}/${new}_${timestamp}"
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
  tmux list-windows -t "$session_name" -F "$format" | while IFS="$S" read -r line; do
    IFS="$S" read -r _ window_index _ _ _ <<<"$line"
    local auto_rename
    auto_rename="$(tmux show-window-options -v -t "$session_name:$window_index" automatic-rename 2>/dev/null)"
    printf "%s%s%s\n" "$line" "$S" "${auto_rename:-on}"
  done >>"$save_file"
}

format_process_command() {
  local pid="$1"
  [[ -r "/proc/${pid}/cmdline" ]] || return 1
  xargs -0 bash -c 'printf "%q " "$0"; for a; do [[ -n "$a" ]] && printf "%q " "$a"; done' <"/proc/${pid}/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//'
}

get_descendant_pids() {
  local root_pid="$1"
  local proc_table
  local -A seen
  local frontier

  [[ -n "$root_pid" ]] || return 1
  proc_table="$(ps -ao ppid=,pid= --sort=pid)"
  frontier="$root_pid"
  seen["$root_pid"]="1"

  while [[ -n "$frontier" ]]; do
    local next_frontier=""
    local ppid
    local pid

    while read -r ppid pid; do
      local parent
      for parent in $frontier; do
        [[ "$ppid" == "$parent" ]] || continue
        [[ -n "${seen[$pid]:-}" ]] && continue
        seen["$pid"]="1"
        printf "%s\n" "$pid"
        next_frontier+=" $pid"
      done
    done <<<"$proc_table"

    frontier="${next_frontier# }"
  done
}

get_process_name() {
  local pid="$1"
  local first_arg
  [[ -r "/proc/${pid}/cmdline" ]] || return 1
  first_arg="$(tr '\0' '\n' <"/proc/${pid}/cmdline" 2>/dev/null | head -n1)"
  [[ -n "$first_arg" ]] || return 1
  basename "$first_arg"
}

select_active_command_pid() {
  local pane_pid="$1"
  local pane_target="$2"
  local pane_current_command
  local pids
  local pid
  local name
  local matching_pid=""
  local fallback_pid=""
  local descendant_count=0

  pane_current_command="$(tmux display-message -p -t "$pane_target" "#{pane_current_command}" 2>/dev/null)"
  pids="$(get_descendant_pids "$pane_pid")"

  for pid in $pids; do
    descendant_count=$((descendant_count + 1))
    fallback_pid="$pid"
    [[ -n "$pane_current_command" ]] || continue
    name="$(get_process_name "$pid")" || continue
    [[ "$name" == "$pane_current_command" ]] && matching_pid="$pid"
  done

  if [[ -n "$matching_pid" ]]; then
    printf "%s" "$matching_pid"
  elif [[ "$descendant_count" == "1" ]]; then
    printf "%s" "$fallback_pid"
  fi
}

_fd_is_pipe() {
  [[ "$(readlink -f "/proc/${1}/fd/${2}" 2>/dev/null)" == pipe:* ]]
}

_order_pipeline() {
  local first="" middle="" last=""
  local pid
  for pid; do
    if ! _fd_is_pipe "$pid" 0 && _fd_is_pipe "$pid" 1; then
      first+=" $pid"
    elif _fd_is_pipe "$pid" 0 && ! _fd_is_pipe "$pid" 1; then
      last+=" $pid"
    else
      middle+=" $pid"
    fi
  done
  printf "%s %s %s" "$first" "$middle" "$last"
}

capture_running_command() {
  local pane_pid="$1"
  local pane_target="$2"
  local command_pid

  command_pid="$(select_active_command_pid "$pane_pid" "$pane_target")"
  [[ -n "$command_pid" ]] || return 1

  local pgid
  pgid="$(ps -o pgid= -p "$command_pid" 2>/dev/null | tr -d ' ')"

  if [[ -z "$pgid" ]]; then
    format_process_command "$command_pid"
    return
  fi

  local pipeline_pids=""
  local pid pid_pgid
  for pid in $(get_descendant_pids "$pane_pid"); do
    pid_pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [[ "$pid_pgid" == "$pgid" ]] || continue
    pipeline_pids+=" $pid"
  done

  pipeline_pids="${pipeline_pids# }"

  local commands=""
  local cmd
  # shellcheck disable=SC2086
  set -- $pipeline_pids
  for pid in $(_order_pipeline "$@"); do
    [[ -z "$pid" ]] && continue
    cmd="$(format_process_command "$pid")" || continue
    [[ -n "$cmd" ]] || continue
    [[ -n "$commands" ]] && commands+=" | "
    commands+="$cmd"
  done

  if [[ -n "$commands" ]]; then
    printf "%s" "$commands"
  else
    format_process_command "$command_pid"
  fi
}

save_panes() {
  local session_name="$1"
  local save_file="$2"
  local format="pane$S#{pane_index}$S#{pane_current_path}$S#{pane_active}$S#{window_index}$S#{pane_pid}"
  tmux list-panes -s -t "$session_name" -F "$format" |
    while IFS="$S" read -r line; do
      local pane_target
      local command
      IFS="$S" read -r _ pane_index _ _ window_index pane_pid <<<"$line"
      pane_target="${session_name}:${window_index}.${pane_index}"
      command="$(capture_running_command "$pane_pid" "$pane_target")"

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
  tmux list-sessions -F "#{session_name} #{status}" | while read -r session status_val; do
  [[ "$status_val" == "off" ]] && continue
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

  local session_path="$(head -n1)"
  [[ -n "$session_path" ]] || session_path="$HOME"
  tmux new-session -ds "$session_name" -c "$session_path"

  local initial_window_index
  initial_window_index=$(tmux list-windows -t "$session_name" -F "#{window_index}" | head -1)
  local initial_window_restored=false

  declare -A window_layouts
  declare active_window
  while read -r line; do
    case $line in
      window*)
        IFS=$S read -r _ window_index window_name window_layout window_active auto_rename <<<"$line"
        [[ -z "$auto_rename" ]] && auto_rename="on"
        window_id="$session_name:$window_index"
        tmux new-window -k -t "$window_id" -n "$window_name"
        if [[ "$auto_rename" == "off" ]]; then
          tmux set-window-option -t "$window_id" automatic-rename off
          tmux rename-window -t "$window_id" "$window_name"
        else
          tmux set-window-option -t "$window_id" automatic-rename on
        fi
        [[ "$window_index" == "$initial_window_index" ]] && initial_window_restored=true
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

  $initial_window_restored || tmux kill-window -t "$session_name:$initial_window_index" 2>/dev/null || true

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
