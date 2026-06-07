#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

main() {
  local session_id="$1"
  local new_name="$2"
  local dir="$(get_opt_dir)"
  local map_file="${dir}/.session_map"

  [[ -z "$session_id" || -z "$new_name" ]] && exit 0

  local old_name=""
  if [[ -f "$map_file" ]]; then
    old_name=$(awk -F'\t' -v id="$session_id" '$1 == id {print $2; exit}' "$map_file")
  fi

  [[ -z "$old_name" || "$old_name" == "$new_name" ]] && exit 0
  [[ -e "${dir}/${new_name}_last" ]] && exit 0

  local old_last="${dir}/${old_name}_last"
  if [[ -L "$old_last" ]]; then
    local actual="$(readlink "$old_last")"
    local actual_basename="$(basename "$actual")"
    local timestamp="${actual_basename: -15}"
    local new_actual="${dir}/${new_name}_${timestamp}"
    mv "$actual" "$new_actual"
    ln -sf "$new_actual" "${dir}/${new_name}_last"
    rm "$old_last"
  fi

  update_session_map
}
main "$@"
