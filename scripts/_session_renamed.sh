#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/sessions.sh"

main() {
  if [[ "${1:-}" == "sync" ]]; then
    sync_session_id_map
    return 0
  fi

  local session_id="$1"
  local new_name="$2"
  handle_session_renamed_hook "$session_id" "$new_name"
}
main "$@"
