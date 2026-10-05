#!/usr/bin/env bash
# skills/go/claim.sh -- claim a staged HANDOFF.md atomically (CONTRACT 4.1, 4.14;
# AMENDMENTS GAP-31, GAP-32, GAP-33).
#
#   claim.sh [--check] [--expect <sha256>] <seat-folder> <handoff-file> <session-id> <seat-name>
#
# --check also prints CONTENT_SHA256, the sha256 of the brief as it stands.
# /go shows the brief to the human and then claims with --expect <that hash>:
# if the file changed in between, the claim refuses with REASON: CHANGED, so
# what runs is exactly what the human saw (AMENDMENTS A-26).
#
# One check path for every TYPE. In order:
#   1. validate the header (CONTRACT 7.2)
#   2. board check, only when MISSION is not NONE (GAP-33)
#   3. mkdir <seat-folder>/.go-claim/<MISSION|SELF>-<WRITTEN as YYYYMMDD-HHMM>
#      (mkdir is atomic: exactly one concurrent caller wins)
#   4. write the claim's owner file
#   5. stamp "ACTIVATED: YYYY-MM-DD HH:MM by <seat> (session <sid8>)" directly
#      under the header (temp file, then mv; never sed -i)
#   6. write the mission claim <team-root>/_claims/<M>.<sid> = "<epoch> <SEAT>"
#      (CONTRACT 7.3), which TARS heartbeats
#   7. prune .go-claim entries and _claims files older than 7 days
# --check runs steps 1 and 2 only and writes nothing, so /go can echo the brief
# and ask about its age before it claims.
#
# Exit codes: 0 claimed (or, with --check, claimable); 3 already claimed or
# already ACTIVATED (prints owner and time); 2 refused, with a line
# "REASON: <TOKEN>", TOKEN one of UNKNOWN_TYPE NO_SEAT NO_WRITTEN SEAT_MISMATCH
# CONSOLIDATED NO_BOARD_ROW NOT_ASSIGNED BOARD_UNREACHABLE, and CHANGED for an
# --expect mismatch. A detail line may follow. Usage errors also exit 2, with
# REASON: UNKNOWN_TYPE when the file cannot be read as a brief: a missing file,
# a HANDOFF.md that is a symlink or a folder, a symlinked .go-claim, or a header
# that runs past line 39 (a stamp under it would fall outside the 40 lines read).
#
# Session id: the go skill passes ${CLAUDE_SESSION_ID}, which Claude Code
# substitutes in skill content ("Available string substitutions",
# https://code.claude.com/docs/en/skills). It is sanitized exactly as
# hooks/tars.sh sanitizes the hook's session_id (keep [A-Za-z0-9_-], first 40
# characters), so /go's claim and TARS's heartbeat name the same file.
#
# Team root: CONTRACT 7.1 applied to the seat folder's parent (GAP-31), with
# the OPS-030 release rule (A-37 P2): the nearest of the parent and the
# grandparent that holds a MISSION_BOARD.md not headed RETIRED BRIDGE COPY.
# Board rows: the "## Active" table only (COLLECTIVE_BOARD.md: any table not
# under an Archive heading). Columns are found by
# header cell: ID, Status, Assignees (the live team writes "Assignee"), Owner.
# A seat is assigned when it is a token of the Assignee(s) or Owner cell (split
# on , / & + and whitespace) or names its own lane in the Status cell.
# A row counts only while in flight: a Status token in ACTIVE QUEUED BLOCKED
# REVIEW PENDING (PENDING is the legacy alias of QUEUED). A row missing from
# ## Active, or one (or this seat's lane) that is COMPLETE, is closed: NO_BOARD_ROW.
# BOARD_UNREACHABLE refuses DISPATCH and CTM-LANE briefs only; a self-handoff
# or informational brief with an unreachable board proceeds without the check.
# CTM-LANE missions live on COLLECTIVE_BOARD.md, read at the team root.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/header.sh"

check=0 expect=""
while :; do
  case ${1:-} in
    --check) check=1; shift ;;
    --expect) [ $# -ge 2 ] || break; expect=$2; shift 2 ;;
    *) break ;;
  esac
done
if [ $# -ne 4 ]; then
  echo "usage: claim.sh [--check] [--expect <sha256>] <seat-folder> <handoff-file> <session-id> <seat-name>" >&2
  echo "REASON: UNKNOWN_TYPE"; exit 2
fi
seatdir=${1%/}; file=$2; rawsid=$3; seat=$4

refuse() { echo "REASON: $1"; [ -n "${2:-}" ] && echo "DETAIL: $2"; exit 2; }

[ -d "$seatdir" ] || refuse UNKNOWN_TYPE "seat folder not found"
[ -L "$file" ] && refuse UNKNOWN_TYPE "the brief is a symlink"
[ -d "$file" ] && refuse UNKNOWN_TYPE "the brief is a folder"
[ -L "$seatdir/.go-claim" ] && refuse UNKNOWN_TYPE ".go-claim is a symlink"
hdr_parse "$file" || refuse UNKNOWN_TYPE "handoff file not readable"
[ "$HDR_LAST" -gt 39 ] && refuse UNKNOWN_TYPE "the header runs past line 39"

# sha256 of a file: sha256sum, else shasum -a 256, else openssl (GAP-12).
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -c1-64
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -c1-64
  else openssl dgst -sha256 < "$1" | sed 's/^.*= *//' | cut -c1-64
  fi
}
content_sha=$(sha_of "$file")
if [ -n "$expect" ] && [ "$expect" != "$content_sha" ]; then
  refuse CHANGED "the brief changed since it was shown (expected $expect, now $content_sha)"
fi

sid=$rawsid
[ "$sid" = '${CLAUDE_SESSION_ID}' ] && sid=""
sid=${sid//[^A-Za-z0-9_-]/}; sid=${sid:0:40}
[ "$sid" = CLAUDE_SESSION_ID ] && sid=""

emit_fields() {
  echo "TYPE=$HDR_TYPE"
  echo "SEAT=$HDR_SEAT"
  echo "MISSION=${HDR_MISSION:-NONE}"
  echo "WRITTEN=$HDR_WRITTEN"
  echo "DISPATCHED_BY=${HDR_DISPATCHER:-}"
  echo "AGE_MIN=$age"
  echo "CONTENT_SHA256=$content_sha"
}

# ---- 1. header
[ -n "$HDR_CONSOLIDATED" ] && refuse CONSOLIDATED "CONSOLIDATED-INTO: $HDR_CONSOLIDATED"
case $HDR_TYPE in
  DISPATCH|SELF-HANDOFF|CTM-LANE|INFORMATIONAL) ;;
  *) refuse UNKNOWN_TYPE "TYPE '${HDR_TYPE:-missing}' is not DISPATCH, SELF-HANDOFF, CTM-LANE or INFORMATIONAL" ;;
esac
[ -n "$HDR_SEAT" ] || refuse NO_SEAT
hdr_seat_matches "$HDR_SEAT" "$seat" || refuse SEAT_MISMATCH "brief is for '$HDR_SEAT', this seat is '$seat'"
[ -n "$HDR_WC" ] || refuse NO_WRITTEN "WRITTEN '${HDR_WRITTEN:-missing}' is not YYYY-MM-DD [HH:MM]"

read -r now_y now_mo now_d now_h now_mi epoch <<EOF
$(date '+%Y %m %d %H %M %s')
EOF
age=$(( ( $(hdr_days "$now_y" "$now_mo" "$now_d") - $(hdr_days "$HDR_Y" "$HDR_MO" "$HDR_D") ) * 1440 \
       + (10#$now_h - 10#$HDR_H) * 60 + (10#$now_mi - 10#$HDR_MI) ))

if [ -n "$HDR_ACTIVATED" ]; then
  echo "ALREADY ACTIVATED: $HDR_ACTIVATED"; exit 3
fi

# ---- 2. board
mission=${HDR_MISSION:-NONE}
[ "$HDR_MISSION" = INVALID ] && mission=INVALID
case $HDR_TYPE in DISPATCH|CTM-LANE) dispatched=1 ;; *) dispatched=0 ;; esac
if [ $dispatched -eq 1 ] && [ "$mission" = NONE ]; then
  refuse NO_BOARD_ROW "a dispatched brief must name its mission ID"
fi
if [ "$mission" = INVALID ]; then
  refuse NO_BOARD_ROW "MISSION '$HDR_MISSION_RAW' holds no mission ID (a capital letter, up to nine more capitals or digits, a dash, a number)"
fi

parent=$(cd "$seatdir/.." 2>/dev/null && pwd -P) || parent=""
root=""
# The nearest live board wins (as in hooks/tars.sh): a seat folder's own
# MISSION_BOARD.md headed RETIRED BRIDGE COPY is a pointer, never a team root,
# and a board planted above the team root can't take it over.
liveboard() {
  local l=""
  [ -f "$1/MISSION_BOARD.md" ] || return 1
  IFS= read -r -n 200 l < "$1/MISSION_BOARD.md"
  case $l in *'RETIRED BRIDGE COPY'*) return 1 ;; esac
  return 0
}
if [ -n "$parent" ]; then
  if liveboard "$parent"; then root=$parent
  elif liveboard "$parent/.."; then root=$(cd "$parent/.." && pwd -P)
  fi
fi

if [ "$mission" != NONE ]; then
  board=""
  if [ -n "$root" ]; then
    if [ "$HDR_TYPE" = CTM-LANE ]; then board="$root/COLLECTIVE_BOARD.md"; else board="$root/MISSION_BOARD.md"; fi
    [ -f "$board" ] && [ -r "$board" ] || board=""
  fi
  if [ -z "$board" ]; then
    [ $dispatched -eq 1 ] && refuse BOARD_UNREACHABLE "no readable board for $mission"
    echo "NOTE: board unreachable; board check skipped for $HDR_TYPE"
  else
    # One line per matching row: section<TAB>status<TAB>assignees<TAB>owner
    row=$(head -c 1048576 "$board" | tr -d '\r' | awk -F'|' -v id="$mission" -v ctm="$([ "$HDR_TYPE" = CTM-LANE ] && echo 1 || echo 0)" '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      /^## / { sec = tolower($0); sub(/^## +/, "", sec); hdr = 0; next }
      /^\|/ {
        if (ctm ? (sec ~ /^archive/) : (sec !~ /^active/)) next
        if (!hdr) {
          ci = si = ai = oi = 0
          for (i = 2; i < NF; i++) {
            c = tolower(trim($i)); gsub(/\*/, "", c)
            if (c == "id") ci = i
            else if (c == "status") si = i
            else if (c == "assignees" || c == "assignee") ai = i
            else if (c == "owner") oi = i
          }
          hdr = 1; next
        }
        if (ci && trim($ci) == id) {
          printf "%s\t%s\t%s\t%s\n", sec, (si ? trim($si) : ""), (ai ? trim($ai) : ""), (oi ? trim($oi) : "")
          exit
        }
        next
      }
      { hdr = 0 }')
    [ -n "$row" ] || refuse NO_BOARD_ROW "$mission is not open on ${board##*/} (## Active)"
    IFS=$'\t' read -r sec status assignees owner <<EOF
$row
EOF
    case $sec in archive*) refuse NO_BOARD_ROW "$mission is archived (closed)" ;; esac
    useat=$(hdr_upper "$seat")
    set -f  # word-split board cells without globbing them
    # Lane-aware status: "alex: ACTIVE / sam: QUEUED".
    lane="" inflight=0 assigned=0
    rest=$(hdr_upper "$status")
    oldifs=$IFS; IFS='/'
    for seg in $rest; do
      hdr_t "$seg"; seg=$HDR_T
      case $seg in
        *:*) hdr_t "${seg%%:*}"; ln=$HDR_T; hdr_t "${seg#*:}"; st=${HDR_T%% *}
             [ "$ln" = "$useat" ] && { lane=$st; assigned=1; } ;;
      esac
    done
    IFS=$oldifs
    for tok in $(printf '%s' "$rest" | tr '/,;:()' '      '); do
      case $tok in ACTIVE|QUEUED|BLOCKED|REVIEW|PENDING) inflight=1 ;; esac
    done
    if [ -n "$lane" ]; then
      case $lane in COMPLETE*) refuse NO_BOARD_ROW "$seat's lane of $mission is COMPLETE" ;; esac
    elif [ $inflight -eq 0 ]; then
      refuse NO_BOARD_ROW "$mission is not in flight (Status: ${status:-empty})"
    fi
    for tok in $(printf '%s,%s' "$(hdr_upper "$assignees")" "$(hdr_upper "$owner")" | tr ',/&+' '    '); do
      [ "$tok" = "$useat" ] && assigned=1
    done
    if [ $assigned -eq 0 ]; then
      oldifs=$IFS; IFS=',/&+'
      for tok in $(hdr_upper "$assignees"),$(hdr_upper "$owner"); do
        hdr_t "$tok"; [ -n "$HDR_T" ] && [ "$HDR_T" = "$useat" ] && assigned=1
      done
      IFS=$oldifs
    fi
    set +f
    [ $assigned -eq 1 ] || refuse NOT_ASSIGNED "$mission is assigned to '${assignees:-nobody}'"
  fi
fi

if [ $check -eq 1 ]; then emit_fields; echo "CLAIMABLE"; exit 0; fi

# ---- 3. claim
if [ "$mission" = NONE ]; then key="SELF-$HDR_WC"; else key="$mission-$HDR_WC"; fi
cdir="$seatdir/.go-claim"
mkdir -p "$cdir" 2>/dev/null
[ -L "$cdir" ] && refuse UNKNOWN_TYPE ".go-claim is a symlink"
if ! mkdir "$cdir/$key" 2>/dev/null; then
  # The winner writes its owner file right after its mkdir; give it up to 3 s.
  o=""; n=0
  while [ ! -f "$cdir/$key/owner" ] && [ $n -lt 30 ]; do sleep 0.1 2>/dev/null || sleep 1; n=$((n+1)); done
  [ -f "$cdir/$key/owner" ] && IFS= read -r o < "$cdir/$key/owner"
  echo "ALREADY CLAIMED: ${o:-by another session (claim in progress)}"; exit 3
fi
stamp_t=$(printf '%s-%s-%s %s:%s' "$now_y" "$now_mo" "$now_d" "$now_h" "$now_mi")
# ---- 4. owner
printf '%s %s session %s at %s\n' "$epoch" "$seat" "${sid:-unknown}" "$stamp_t" > "$cdir/$key/.owner.$$" \
  && mv -f "$cdir/$key/.owner.$$" "$cdir/$key/owner"

# ---- 5. stamp (re-read under the claim: a stamp written since step 1 wins,
# and an --expect hash is checked again against the file we are about to stamp)
hdr_parse "$file"
if [ -n "$HDR_ACTIVATED" ]; then echo "ALREADY ACTIVATED: $HDR_ACTIVATED"; exit 3; fi
if [ -n "$expect" ] && [ "$expect" != "$(sha_of "$file")" ]; then
  rm -rf "${cdir:?}/$key"
  refuse CHANGED "the brief changed while it was being claimed"
fi
eol=""; [ "$HDR_CRLF" = 1 ] && eol=$'\r'
st_line="ACTIVATED: $stamp_t by $seat (session ${sid:0:8})"
[ -n "$sid" ] || st_line="ACTIVATED: $stamp_t by $seat"
tmpf="$file.claim.$$"
# head and tail copy bytes as they are, so CRLF and a missing final newline survive.
{ head -n "$HDR_LAST" "$file"; printf '%s\n' "$st_line$eol"; tail -n +"$((HDR_LAST + 1))" "$file"; } > "$tmpf" && mv -f "$tmpf" "$file"
rm -f "$tmpf" 2>/dev/null

# ---- 6. mission claim (CONTRACT 7.3)
if [ "$mission" != NONE ] && [ -n "$sid" ] && [ -n "$root" ] && [[ $mission =~ $HDR_RE_MEXACT ]]; then
  cl="$root/_claims"
  if [ -L "$cl" ]; then
    echo "NOTE: $cl is a symlink; mission claim not written"
  else
    mkdir -p "$cl" 2>/dev/null
    sf=${seat//[^A-Za-z0-9 ._()-]/}; sf=${sf:0:60}; [ -n "$sf" ] || sf=unknown
    printf '%s %s\n' "$epoch" "$sf" > "$cl/.tmp.$$" && mv -f "$cl/.tmp.$$" "$cl/$mission.$sid"
  fi
fi

# ---- 7. prune (content epochs; no stat, per GAP-12)
old=$(( epoch - 7*86400 ))
for d in "$cdir"/*/; do
  [ -d "$d" ] || continue
  o=""; [ -f "$d/owner" ] && IFS= read -r o < "$d/owner"; e=${o%% *}
  case $e in ''|*[!0-9]*) continue ;; esac
  [ "$e" -lt "$old" ] && rm -rf "${d%/}"
done
if [ -n "$root" ] && [ -d "$root/_claims" ] && [ ! -L "$root/_claims" ]; then
  for c in "$root/_claims"/*.*; do
    [ -f "$c" ] && [ ! -L "$c" ] || continue
    o=""; IFS= read -r o < "$c"; e=${o%% *}
    case $e in ''|*[!0-9]*) continue ;; esac
    [ ${#e} -le 12 ] && [ "$e" -lt "$old" ] && rm -f "$c"
  done
fi

emit_fields
echo "CLAIMED $key"
exit 0
