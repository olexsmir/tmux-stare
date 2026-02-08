#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/sessions.sh"

main() {
  local interval=$(get_opt_interval)
  [[ "$interval" == "0" ]] && exit 0

  local last=$(get_opt_last)
  local now=$(date +%s)

  if [[ $((now - last)) -ge $((interval * 60)) ]]; then
    save_all_sessions
    set_opt_last "$now"
  fi
}
main
