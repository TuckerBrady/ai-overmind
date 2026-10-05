#!/usr/bin/env bash
# skills/dispatch/alloc-id.sh -- allocate the next mission ID without a race
# (CONTRACT 4.4, AMENDMENTS GAP-39).
#
#   alloc-id.sh <team-root> <PREFIX>
#
# PREFIX matches ^[A-Z]{2,5}$. The next number is 1 + the largest N of any
# PREFIX-N in the first cell of a row in the board's "## Active" and
# "## Archive" tables (MISSION_BOARD.md) and of any <team-root>/_ids/PREFIX-N
# entry. The ID is then claimed with mkdir <team-root>/_ids/<ID>, which is
# atomic: on a collision the number goes up by one and the claim is retried.
# Prints the ID (zero-padded to three digits, as the team's board does) and
# exits 0. Exit 2 on a bad argument or when no ID can be claimed.
#
# A team whose board lives in a database with a write script
# (<team-root>/_Team/team.py) allocates through that script instead; this is
# the fallback for teams without one (see reference/dispatch.md).
set -u
[ $# -eq 2 ] || { echo "usage: alloc-id.sh <team-root> <PREFIX>" >&2; exit 2; }
root=${1%/}; prefix=$2
[[ $prefix =~ ^[A-Z]{2,5}$ ]] || { echo "alloc-id: prefix must be 2-5 capital letters" >&2; exit 2; }
[ -d "$root" ] || { echo "alloc-id: no team root at $root" >&2; exit 2; }
ids="$root/_ids"
if [ -L "$ids" ]; then echo "alloc-id: $ids is a symlink; refusing" >&2; exit 2; fi
mkdir -p "$ids" 2>/dev/null || { echo "alloc-id: cannot create $ids" >&2; exit 2; }

max=0
if [ -f "$root/MISSION_BOARD.md" ]; then
  m=$(head -c 1048576 "$root/MISSION_BOARD.md" | tr -d '\r' | awk -F'|' -v p="$prefix" '
    /^## / { s = tolower($0); sub(/^## +/, "", s); on = (s ~ /^(active|archive)/); next }
    on && /^\|/ {
      c = $2; gsub(/^[ \t*]+|[ \t*]+$/, "", c)
      if (c ~ ("^" p "-[0-9]+[a-z]?$")) { sub(/^[A-Z]+-/, "", c); sub(/[a-z]$/, "", c); n = c + 0; if (n > max) max = n }
    }
    END { print max + 0 }')
  max=$m
fi
for e in "$ids/$prefix"-*; do
  [ -e "$e" ] || continue
  n=${e##*/}; n=${n#"$prefix"-}
  case $n in ''|*[!0-9]*) continue ;; esac
  [ "$((10#$n))" -gt "$max" ] && max=$((10#$n))
done

n=$((max + 1)); tries=0
while [ $tries -lt 1000 ]; do
  id=$(printf '%s-%03d' "$prefix" "$n")
  if mkdir "$ids/$id" 2>/dev/null; then echo "$id"; exit 0; fi
  n=$((n + 1)); tries=$((tries + 1))
done
echo "alloc-id: no free ID after 1000 tries" >&2
exit 2
