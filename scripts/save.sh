#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# TODO: save all sessions

# # TODO: save all loaded sessions not only current
# main() {
#   local session_name="${1:-$(get_current_session_name)}"
#   start_spinner "Saving session: $session_name"
#   save_session "$session_name"
#   stop_spinner "Session saved"
# }
# main "$@"
