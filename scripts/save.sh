#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

declare S=$'\t'

save_cwd() {
  local save_file="$1"
  tmux -c pwd >>"$save_file"
}

save_windows() {
  local save_file="$1"
  local format="window$S#{window_index}$S#{window_name}$S#{window_layout}$S#{window_active}"
  tmux list-windows -F "$format" >>"$save_file"
}

save_panes() {
  local save_file="$1"
  local format="pane$S#{pane_index}$S#{pane_current_path}$S#{pane_active}$S#{window_index}$S#{pane_pid}"
  tmux list-panes -s -F "$format" |
    while IFS="$S" read -r line; do
      pids=$(ps -ao "ppid,pid" |
        sed "s/^ *//" |
        grep "^$(cut -f6 <<<"$line")" |
        rev |
        cut -d' ' -f1 |
        rev)

      command="$(
        for pid in $pids; do
          while read -r arg; do
            echo -n "'$arg' "
          done <<<"$(xargs -0L1 </proc/"$pid"/cmdline)"
        done
      )"

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

# TODO: add interval saves (tmux-continuum like)
# TODO: save all loaded sessions not only current
# TODO: link last session saved as last
main() {
  start_spinner "Saving current session"
  local save_dir="$(get_opt_dir)"
  local save_file="${save_dir}/$(get_current_session_name)_$(get_time)"
  local last_file="${save_dir}/$(get_current_session_name)_last"
  save_cwd "$save_file"
  save_windows "$save_file"
  save_panes "$save_file"
  link_session_last "$save_file" "$last_file"
  link_last "$last_file" "$save_dir"
  stop_spinner "Session saved"
}
main
