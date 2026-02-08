get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local option_value=$(tmux show-option -gqv "$option")
  if [ -z "$option_value" ]; then
    echo "$default_value"
  else
    echo "$option_value"
  fi
}

set_tmux_option() {
  local option="$1"
  local value="$2"
  tmux set-option -gq "$option" "$value"
}

get_time() { date +"%Y%m%dT%H%M%S"; }

# === options
get_opt_interval() { get_tmux_option "@stare-interval" "10"; }
get_opt_save() { get_tmux_option "@stare-save" "C-s"; }
get_opt_pick() { get_tmux_option "@stare-pick" ""; }
get_opt_dir() {
  local dir="$(get_tmux_option "@stare-dir" "${HOME}/.local/share/tmux/stare" | sed "s,\$HOME,$HOME,g; s,\~,$HOME,g")"
  mkdir -p "$dir"
  echo "$dir"
}

# === spiner
# TODO: use one of those  briael fonts
new_spinner() {
  local current=0
  local -r chars="/-\|"
  while true; do
    tmux display-message -- "${chars:$current:1} $1"
    current=$(((current + 1) % 4))
    sleep 0.1
  done
}

start_spinner() {
  new_spinner "$1" &
  export SPINNER_PID=$!
}

stop_spinner() {
  kill "$SPINNER_PID"
  tmux display-message "$1"
}

get_current_session_name() {
  if [ "$(tmux display-message -p "#{session_grouped}")" = 0 ]; then
    tmux display-message -p "#{session_name}" 2>/dev/null || true
  else
    tmux display-message -p "#{session_group}" 2>/dev/null || true
  fi
}
