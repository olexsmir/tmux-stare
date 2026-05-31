#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

wait_for_client
tmux display-popup -E -w 25% -h 50% "$CURRENT_DIR/pick.sh"
