#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux display-popup -E -w 25% -h 50% "$CURRENT_DIR/pick.sh"
