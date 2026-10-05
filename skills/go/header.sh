# skills/go/header.sh -- the one HANDOFF header parser (CONTRACT 7.2), sourced
# by claim.sh and handoff.sh. Not executable on its own.
#
# The v5 header is plain lines at the top of the file:
#   TYPE: DISPATCH | SELF-HANDOFF | CTM-LANE | INFORMATIONAL
#   SEAT: <seat>   MISSION: <ID> | NONE   WRITTEN: YYYY-MM-DD HH:MM
#   DISPATCHED BY: <seat>   (DISPATCH and CTM-LANE only)
# followed by the stamps ACTIVATED: ... and CONSOLIDATED-INTO: ...
#
# The parser is tolerant of every format the live team has written:
#   - legacy bold fields (**TYPE:** x) and whole bold lines (**TYPE: x · SEAT: y**)
#   - several fields on one line, separated by " · "
#   - a value followed by commentary: "SELF-HANDOFF (seat handoff)",
#     "AXM-046 - repair arc", "2026-09-26 11:55 MDT, by ..."
#   - date-only WRITTEN (compact time 0000), MISSIONS: and MISSION ID: aliases
# Only the first 40 lines (and at most 64 KiB) are read. A field counts only
# when it opens a line or a " · " segment, so prose such as "stamp ACTIVATED:
# under the header" in a template's body is never a stamp.
#
# Bash 3.2 safe: no associative arrays, no case-modifying expansions.

HDR_RE_FIELD='^(TYPE|SEAT|MISSIONS|MISSION ID|MISSION|WRITTEN|DISPATCHED BY|ACTIVATED|CONSOLIDATED-INTO):[[:space:]]*(.*)$'

# Mission ID, CONTRACT 7.3 as amended by A-17 (single-letter prefixes such as M-017 are valid).
HDR_RE_MEXACT='^[A-Z][A-Z0-9]{0,9}-[0-9]{1,5}[a-z]?$'
HDR_RE_DATE='([0-9]{4})-([0-9]{2})-([0-9]{2})([ T]([0-9]{2}):([0-9]{2}))?'
HDR_RE_TYPE='^([A-Za-z-]+)'
# Stamps match case-insensitively (A-26): "activated:" is a stamp too.
HDR_RE_STAMP='^(ACTIVATED|CONSOLIDATED-INTO):[[:space:]]*(.*)$'
HDR_EMDASH=$'\xe2\x80\x94'

hdr_t() { # STRING -> HDR_T, trimmed (no subshell, so no fork)
  HDR_T=$1
  HDR_T=${HDR_T#"${HDR_T%%[![:space:]]*}"}
  HDR_T=${HDR_T%"${HDR_T##*[![:space:]]}"}
}

hdr_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# hdr_parse FILE. Sets:
#   HDR_TYPE (uppercased first word, or "") HDR_SEAT HDR_MISSION (an ID, NONE,
#   or "" when absent) HDR_MISSION_RAW HDR_WRITTEN (raw) HDR_WC (YYYYMMDD-HHMM
#   or "") HDR_DISPATCHER HDR_ACTIVATED HDR_CONSOLIDATED HDR_LAST (line number
#   of the last header-field line, 0 if none) HDR_CRLF (1 when the file's first
#   line ends in CR).
hdr_parse() {
  local f=$1 n=0 line seg rest key val tok nc dot=' '$'\xc2\xb7'' ' cr=$'\r'
  HDR_TYPE="" HDR_SEAT="" HDR_MISSION="" HDR_MISSION_RAW="" HDR_WRITTEN="" HDR_WC=""
  HDR_DISPATCHER="" HDR_ACTIVATED="" HDR_CONSOLIDATED="" HDR_LAST=0 HDR_CRLF=0
  HDR_Y="" HDR_MO="" HDR_D="" HDR_H="" HDR_MI=""
  [ -f "$f" ] && [ -r "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1)); [ $n -gt 40 ] && break
    case $line in *"$cr") [ $n -eq 1 ] && HDR_CRLF=1; line=${line%"$cr"} ;; esac
    line=${line:0:4096}
    line=${line//\*/}
    # Leading blockquote markers and whitespace.
    while :; do
      case $line in
        ' '*|$'\t'*|'>'*) line=${line:1} ;;
        [-+]' '*) line=${line:2} ;;
        [0-9]'. '*|[0-9][0-9]'. '*) line=${line#*. } ;;
        *) break ;;
      esac
    done
    rest=$line
    while [ -n "$rest" ]; do
      case $rest in
        *"$dot"*) seg=${rest%%"$dot"*}; rest=${rest#*"$dot"} ;;
        *) seg=$rest; rest="" ;;
      esac
      hdr_t "$seg"; seg=$HDR_T
      if [[ $seg =~ $HDR_RE_FIELD ]]; then
        key=${BASH_REMATCH[1]}; hdr_t "${BASH_REMATCH[2]}"; val=$HDR_T
      else
        shopt -q nocasematch && nc=1 || nc=0
        shopt -s nocasematch
        if [[ $seg =~ $HDR_RE_STAMP ]]; then
          key=$(hdr_upper "${BASH_REMATCH[1]}"); hdr_t "${BASH_REMATCH[2]}"; val=$HDR_T
        else key=""; fi
        [ $nc -eq 1 ] || shopt -u nocasematch
        [ -n "$key" ] || continue
      fi
      HDR_LAST=$n
      case $key in
        TYPE) [ -z "$HDR_TYPE" ] && [[ $val =~ $HDR_RE_TYPE ]] && HDR_TYPE=$(hdr_upper "${BASH_REMATCH[1]}") ;;
        SEAT) [ -z "$HDR_SEAT" ] && HDR_SEAT=$val ;;
        MISSION|MISSIONS|"MISSION ID")
          if [ -z "$HDR_MISSION_RAW" ]; then
            HDR_MISSION_RAW=${val:-NONE}
            case $(hdr_upper "$val") in
              ''|NONE|NONE[!A-Z0-9]*|N/A|N/A[!A-Z0-9]*|-) HDR_MISSION=NONE ;;
              *) # The ID is the value's first word, brackets and trailing punctuation
               # stripped, and it must match the 7.3 regex exactly: "AXM-046 - text"
               # gives AXM-046; "m-017", "-17", "M-" and "xM-017" give INVALID.
               tok=${val%%[[:space:]]*}; tok=${tok#[\[(]}; tok=${tok%%[\]),;:.]*}
               if [[ $tok =~ $HDR_RE_MEXACT ]]; then HDR_MISSION=$tok; else HDR_MISSION=INVALID; fi ;;
            esac
          fi ;;
        WRITTEN)
          if [ -z "$HDR_WRITTEN" ]; then
            HDR_WRITTEN=$val
            if [[ $val =~ $HDR_RE_DATE ]]; then
              HDR_Y=${BASH_REMATCH[1]} HDR_MO=${BASH_REMATCH[2]} HDR_D=${BASH_REMATCH[3]}
              HDR_H=${BASH_REMATCH[5]:-00} HDR_MI=${BASH_REMATCH[6]:-00}
              if [ $((10#$HDR_MO)) -ge 1 ] && [ $((10#$HDR_MO)) -le 12 ] && [ $((10#$HDR_D)) -ge 1 ] \
                 && [ $((10#$HDR_D)) -le 31 ] && [ $((10#$HDR_H)) -le 23 ] && [ $((10#$HDR_MI)) -le 59 ]; then
                HDR_WC="$HDR_Y$HDR_MO$HDR_D-$HDR_H$HDR_MI"
              fi
            fi
          fi ;;
        "DISPATCHED BY") [ -z "$HDR_DISPATCHER" ] && HDR_DISPATCHER=$val ;;
        ACTIVATED) [ -z "$HDR_ACTIVATED" ] && HDR_ACTIVATED=${val:-stamped} ;;
        CONSOLIDATED-INTO) [ -z "$HDR_CONSOLIDATED" ] && HDR_CONSOLIDATED=${val:-stamped} ;;
      esac
    done
  done < <(head -c 65536 "$f" 2>/dev/null)
  return 0
}

# hdr_seat_matches HEADER_SEAT SEAT_NAME: case-insensitive; the header value
# may carry commentary after the name ("Nash (WRENCH)", "Nash, developer").
hdr_seat_matches() {
  local h w
  hdr_t "$1"; h=$(hdr_upper "$HDR_T"); hdr_t "$2"; w=$(hdr_upper "$HDR_T")
  [ -n "$w" ] || return 1
  h=${h%% (*}; h=${h%%,*}; h=${h%% - *}; h=${h%% "$HDR_EMDASH"*}
  hdr_t "$h"
  [ "$HDR_T" = "$w" ]
}

# hdr_days Y M D -> days since 1970-01-01 (proleptic Gregorian), no date -d.
hdr_days() {
  local y=$((10#$1)) m=$((10#$2)) d=$((10#$3)) era yoe doy doe
  [ $m -le 2 ] && y=$((y-1))
  if [ $y -ge 0 ]; then era=$((y/400)); else era=$(((y-399)/400)); fi
  yoe=$((y - era*400))
  if [ $m -gt 2 ]; then doy=$(( (153*(m-3) + 2)/5 + d - 1 )); else doy=$(( (153*(m+9) + 2)/5 + d - 1 )); fi
  doe=$(( yoe*365 + yoe/4 - yoe/100 + doy ))
  printf '%s' $(( era*146097 + doe - 719468 ))
}
