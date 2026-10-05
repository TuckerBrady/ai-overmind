#!/usr/bin/env bash
# skills/go/handoff.sh -- the only way a brief lands in a seat folder
# (CONTRACT 4.2, 4.3, 7.2).
#
#   handoff.sh place <seat-folder> <new-file>
#     Puts <new-file> at <seat-folder>/HANDOFF.md, the canonical path. If a
#     HANDOFF.md is already there and carries neither an ACTIVATED: nor a
#     CONSOLIDATED-INTO: stamp, nobody has taken it yet, so it is never
#     overwritten: it is renamed HANDOFF.superseded-<YYYYMMDD-HHMM>.md (a -2,
#     -3 ... suffix if that name is taken) and the new name is printed as
#     "SUPERSEDED: <name>". A stamped brief is simply replaced. Then the new
#     file is moved into place and "PLACED: <path>" is printed.
#
#   handoff.sh migrate <seat-folder>
#     <seat-folder>/.auto-memory/HANDOFF.md is a legacy read path only. When it
#     exists and the canonical file does not, or the legacy copy's WRITTEN is
#     later than the canonical one's, the legacy brief is copied to the
#     canonical path (through place, so an untaken canonical brief is
#     superseded, never lost) and the legacy file is renamed
#     .auto-memory/HANDOFF.migrated-<YYYYMMDD-HHMM>.md (the legacy copy, kept). Prints "MIGRATED: <name>"
#     or "CURRENT: <canonical path>" (nothing to do), or "NONE" when neither
#     file exists.
#
#     When both copies exist, differ, and either one has no usable WRITTEN date,
#     nothing moves: it prints "ASK:" with both paths, and /go shows both to the
#     human and asks which one to run.
#
# Both commands work under a lock (mkdir <seat-folder>/.handoff.lock; a lock
# older than 30 s is taken as stale), so concurrent placements never lose a
# brief, and the superseded name is chosen under the lock without clobbering.
# A HANDOFF.md that is a symlink or a folder is refused ("REFUSED: ...", exit 2).
#
# Exit 0 on success, 2 on a usage error, a refusal, a lock timeout or a failed
# move.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/header.sh"

usage() { echo "usage: handoff.sh place <seat-folder> <new-file> | handoff.sh migrate <seat-folder>" >&2; exit 2; }
ts=$(date '+%Y%m%d-%H%M')

LOCK=""
unlock() { [ -n "$LOCK" ] && rm -rf "$LOCK"; LOCK=""; }
trap unlock EXIT
lock() { # seat-folder: take <seat>/.handoff.lock, waiting up to 15 s
  local l="$1/.handoff.lock" n=0 e now
  while ! mkdir "$l" 2>/dev/null; do
    e=""; [ -f "$l/at" ] && IFS= read -r e < "$l/at"
    now=$(date +%s)
    case $e in ''|*[!0-9]*) ;; *) [ $((now - e)) -gt 30 ] && { rm -rf "$l"; continue; } ;; esac
    n=$((n + 1)); [ $n -gt 150 ] && { echo "REFUSED: $l is held" >&2; exit 2; }
    sleep 0.1 2>/dev/null || sleep 1
  done
  date +%s > "$l/at"; LOCK=$l
}
refuse_shape() { # path
  [ -L "$1" ] && { echo "REFUSED: ${1##*/} is a symlink"; exit 2; }
  [ -d "$1" ] && { echo "REFUSED: ${1##*/} is a folder"; exit 2; }
  return 0
}

free_name() { # DIR BASE -> first unused DIR/BASE-ts.md, DIR/BASE-ts-2.md, ...
  local n="$1/$2-$ts.md" i=2
  while [ -e "$n" ]; do n="$1/$2-$ts-$i.md"; i=$((i+1)); done
  printf '%s' "$n"
}

place() { # seat-folder new-file
  local seat=${1%/} new=$2 cur sup took=0
  [ -d "$seat" ] && [ -f "$new" ] || usage
  cur="$seat/HANDOFF.md"
  refuse_shape "$cur"
  [ -n "$LOCK" ] || { lock "$seat"; took=1; }
  refuse_shape "$cur"
  if [ -f "$cur" ]; then
    hdr_parse "$cur"
    if [ -z "$HDR_ACTIVATED" ] && [ -z "$HDR_CONSOLIDATED" ]; then
      sup=$(free_name "$seat" HANDOFF.superseded)
      [ -e "$sup" ] && exit 2
      mv "$cur" "$sup" || exit 2
      echo "SUPERSEDED: ${sup##*/}"
    fi
  fi
  mv -f "$new" "$cur" || exit 2
  echo "PLACED: $cur"
  [ $took -eq 1 ] && unlock
  return 0
}

migrate() { # seat-folder
  local seat=${1%/} cur leg cwc tmp mig
  [ -d "$seat" ] || usage
  cur="$seat/HANDOFF.md"; leg="$seat/.auto-memory/HANDOFF.md"  # legacy read path
  refuse_shape "$cur"; refuse_shape "$leg"
  lock "$seat"
  if [ ! -f "$leg" ]; then
    if [ -f "$cur" ]; then echo "CURRENT: $cur"; else echo "NONE"; fi
    return 0
  fi
  if [ -f "$cur" ]; then
    hdr_parse "$cur"; cwc=$HDR_WC
    hdr_parse "$leg"
    if cmp -s "$cur" "$leg"; then echo "CURRENT: $cur"; return 0; fi
    if [ -z "$HDR_WC" ] || [ -z "$cwc" ]; then
      echo "ASK: both copies exist, they differ, and one has no WRITTEN date"
      echo "CANONICAL: $cur"
      echo "LEGACY: $leg"
      return 0
    fi
    if [ ! "$HDR_WC" \> "$cwc" ]; then
      # The legacy copy is not newer: canonical wins.
      echo "CURRENT: $cur"; return 0
    fi
  fi
  tmp="$seat/.HANDOFF.migrating.$$"
  cp "$leg" "$tmp" || exit 2
  place "$seat" "$tmp" || exit 2
  mig=$(free_name "$seat/.auto-memory" HANDOFF.migrated)
  mv "$leg" "$mig" || exit 2
  echo "MIGRATED: .auto-memory/${mig##*/}"
}

case ${1:-} in
  place) [ $# -eq 3 ] || usage; place "$2" "$3" ;;
  migrate) [ $# -eq 2 ] || usage; migrate "$2" ;;
  *) usage ;;
esac
exit 0
