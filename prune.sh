#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

set -euo pipefail

DAYS=7

DIR="$(get_opt_dir)"
cd "$DIR"

CUTOFF=$(date -d "$DAYS days ago" +%Y%m%dT%H%M%S)

# Build set of active session names (those with a _last symlink)
declare -A ACTIVE
for l in *_last; do
  [ -L "$l" ] || continue
  ACTIVE["${l%_last}"]=1
done

DELETED=0
FIXED=0

for f in *_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]; do
  [ -f "$f" ] || continue
  name="${f%_*}"
  ts="${f##*_}"

  if [[ -v ACTIVE["$name"] ]]; then
    # Active session: keep the _last target always, prune old others
    target="$(readlink "$name"_last 2>/dev/null || true)"
    if [ "$f" = "$target" ]; then continue; fi  # always keep the _last target
    if [[ "$ts" < "$CUTOFF" ]]; then
      rm "$f"
      echo "pruned: $f"
      DELETED=$((DELETED + 1))
    fi
  else
    # Orphaned session: delete everything
    rm "$f"
    echo "pruned (orphan): $f"
    DELETED=$((DELETED + 1))
  fi
done

# Clean dangling _last symlinks (target was deleted)
for l in *_last; do
  [ -L "$l" ] || continue
  [ -e "$l" ] && continue
  rm "$l"
  echo "cleaned: $l (broken symlink)"
  FIXED=$((FIXED + 1))
done

# Clean dangling global last symlink
if [ -L "last" ] && [ ! -e "last" ]; then
  rm "last"
  echo "cleaned: last (broken symlink)"
  FIXED=$((FIXED + 1))
fi

echo "Done. $DELETED session files pruned, $FIXED broken symlinks cleaned."
