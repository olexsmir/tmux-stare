#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

set -euo pipefail
cd "$(get_opt_dir)"

DAYS=7

CUTOFF=$(date -d "$DAYS days ago" +%Y%m%dT%H%M%S)


RED='\033[0;31m'
MAGENTA='\033[0;35m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# Build set of active session names (those with a _last symlink)
declare -A ACTIVE
for l in *_last; do
  [ -L "$l" ] || continue
  ACTIVE["${l%_last}"]=1
done

DELETED=0
ORPHANS=0
FIXED=0

for f in *_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]; do
  [ -f "$f" ] || continue
  name="${f%_*}"
  ts="${f##*_}"

  if [[ -v ACTIVE["$name"] ]]; then
    # Active session: keep the _last target always, prune old others
    target="$(readlink "$name"_last 2>/dev/null || true)"
    if [ "$f" = "$target" ]; then continue; fi # always keep the _last target
    if [[ "$ts" < "$CUTOFF" ]]; then
      rm "$f"
      echo -e "${RED}pruned:${RESET} $f"
      DELETED=$((DELETED + 1))
    fi
  else
    # Orphaned session: delete everything
    rm "$f"
    echo -e "${MAGENTA}pruned (orphan):${RESET} $f"
    DELETED=$((DELETED + 1))
    ORPHANS=$((ORPHANS + 1))
  fi
done

# Clean dangling _last symlinks (target was deleted)
for l in *_last; do
  [ -L "$l" ] || continue
  [ -e "$l" ] && continue
  rm "$l"
  echo -e "${YELLOW}cleaned:${RESET} $l (broken symlink)"
  FIXED=$((FIXED + 1))
done

# Clean dangling global last symlink
if [ -L "last" ] && [ ! -e "last" ]; then
  rm "last"
  echo -e "${YELLOW}cleaned:${RESET} last (broken symlink)"
  FIXED=$((FIXED + 1))
fi

echo "Done. $DELETED session files pruned, $ORPHANS orphan sessions deleted, $FIXED broken symlinks cleaned."
