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
# Exit 0 on success, 2 on a usage error or a failed move.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/header.sh"

usage() { echo "usage: handoff.sh place <seat-folder> <new-file> | handoff.sh migrate <seat-folder>" >&2; exit 2; }
ts=$(date '+%Y%m%d-%H%M')

free_name() { # DIR BASE -> first unused DIR/BASE-ts.md, DIR/BASE-ts-2.md, ...
  local n="$1/$2-$ts.md" i=2
  while [ -e "$n" ]; do n="$1/$2-$ts-$i.md"; i=$((i+1)); done
  printf '%s' "$n"
}

place() { # seat-folder new-file
  local seat=${1%/} new=$2 cur sup
  [ -d "$seat" ] && [ -f "$new" ] || usage
  cur="$seat/HANDOFF.md"
  if [ -f "$cur" ]; then
    hdr_parse "$cur"
    if [ -z "$HDR_ACTIVATED" ] && [ -z "$HDR_CONSOLIDATED" ]; then
      sup=$(free_name "$seat" HANDOFF.superseded)
      mv "$cur" "$sup" || exit 2
      echo "SUPERSEDED: ${sup##*/}"
    fi
  fi
  mv -f "$new" "$cur" || exit 2
  echo "PLACED: $cur"
}

migrate() { # seat-folder
  local seat=${1%/} cur leg cwc tmp mig
  [ -d "$seat" ] || usage
  cur="$seat/HANDOFF.md"; leg="$seat/.auto-memory/HANDOFF.md"  # legacy read path
  if [ ! -f "$leg" ]; then
    if [ -f "$cur" ]; then echo "CURRENT: $cur"; else echo "NONE"; fi
    return 0
  fi
  if [ -f "$cur" ]; then
    hdr_parse "$cur"; cwc=$HDR_WC
    hdr_parse "$leg"
    if cmp -s "$cur" "$leg" || [ -z "$HDR_WC" ] || [ -z "$cwc" ] || [ ! "$HDR_WC" \> "$cwc" ]; then
      # Same brief, or the legacy copy is not provably newer: canonical wins.
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
