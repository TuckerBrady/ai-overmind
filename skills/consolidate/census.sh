#!/usr/bin/env bash
# census.sh <team-root> <ID> <projects-dir> <SEAT>
#
# /consolidate's CLI-fallback census (CONTRACT 6.10, GAP-46), for a runtime
# with no desktop session tools. Lists, one per line, tab-separated:
#
#   claim<TAB><sid><TAB><epoch><TAB><path>
#       each <team-root>/_claims/<ID>.<sid> whose content's SEAT field is
#       <SEAT>. A claim held by another seat is a lane, not a duplicate: it is
#       never listed.
#   transcript<TAB><session-id><TAB><cwd><TAB><path>
#       each <projects-dir>/*.jsonl or <projects-dir>/*/*.jsonl modified in
#       the last 7 days whose text names <ID> as a whole token. cwd is the
#       first "cwd" the transcript records ("-" if none). Subagent
#       transcripts deeper down are not sessions and are not listed.
#
# cwd never identifies a mission on its own (every session of a seat shares
# one), and a transcript hit is a candidate, not a verdict: the skill
# classifies each one. Claim content is read through a 256-byte bound.
# Exit 0 on success (an empty census included), 2 on bad usage.
set -u
usage() { echo "usage: census.sh <team-root> <ID> <projects-dir> <SEAT>" >&2; exit 2; }
[ $# -eq 4 ] || usage
root=$1; id=$2; proj=$3; seat=$4
printf '%s\n' "$id" | LC_ALL=C grep -qxE '[A-Z][A-Z0-9]{1,9}-[0-9]{1,5}[a-z]?' || usage
[ -n "$seat" ] || usage
case $seat in *[[:cntrl:]]*) usage ;; esac

clean() { LC_ALL=C tr -d '\000-\010\013-\037\177' | tr '\t\n' '  '; }

# --- claims ------------------------------------------------------------------------
cl="$root/_claims"
if [ -d "$cl" ] && [ ! -L "$cl" ]; then
  for f in "$cl/$id".*; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    sid=${f##*/}; sid=${sid#"$id".}
    printf '%s\n' "$sid" | LC_ALL=C grep -qxE '[A-Za-z0-9_-]{1,40}' || continue
    line=$(head -c 256 "$f" | head -n 1 | tr -d '\r')
    ep=${line%% *}; who=${line#* }
    case $ep in ''|*[!0-9]*) continue ;; esac
    [ "$line" != "$ep" ] || continue
    [ "$who" = "$seat" ] || continue
    printf 'claim\t%s\t%s\t%s\n' "$sid" "$ep" "$f"
  done
fi

# --- transcripts -------------------------------------------------------------------
if [ -d "$proj" ]; then
  re="(^|[^A-Za-z0-9])$id([^A-Za-z0-9]|\$)"
  find "$proj" -maxdepth 2 -type f -name '*.jsonl' -mtime -7 2>/dev/null | LC_ALL=C sort |
  while IFS= read -r t; do
    LC_ALL=C grep -qE -- "$re" "$t" 2>/dev/null || continue
    s=${t##*/}; s=${s%.jsonl}
    cwd=$(LC_ALL=C grep -m 1 -oE '"cwd": ?"[^"]*"' "$t" 2>/dev/null | head -n 1)
    cwd=${cwd#*:}; cwd=${cwd# }; cwd=${cwd#\"}; cwd=${cwd%\"}
    cwd=$(printf '%s' "${cwd:--}" | sed 's/\\\\/\\/g' | clean)
    printf 'transcript\t%s\t%s\t%s\n' "$(printf '%s' "$s" | clean)" "${cwd:0:300}" "$t"
  done
fi
exit 0
