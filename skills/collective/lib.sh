#!/usr/bin/env bash
# skills/collective/lib.sh: shared helpers for the Collective scripts
# (proof.sh, state.sh, catchup.sh, post-name.sh, and ../assimilate/genesis.sh).
# Sourced, never run. Formats are reference/collective.md "Formats (7.10)".
#
# Portability (CONTRACT 0.4, GAP-12): POSIX utilities only. sha256 via
# sha256sum, then shasum -a 256, then openssl dgst -sha256. Random via
# od -An -tx1 -N<n> /dev/urandom. No stat, no date -d, no sed -i, no jq.
# Runs under bash 3.2 and 5.x.

# die CODE MESSAGE: print to stderr and exit.
die() { printf '%s\n' "$2" >&2; exit "$1"; }

# The sha256 tool, chosen once: sha256sum, then shasum -a 256, then openssl.
if command -v sha256sum >/dev/null 2>&1; then SHA_TOOL=sha256sum
elif command -v shasum >/dev/null 2>&1; then SHA_TOOL=shasum
elif command -v openssl >/dev/null 2>&1; then SHA_TOOL=openssl
else SHA_TOOL=""; fi

# sha_hex: lowercase sha256 hex of stdin. All three tools print lowercase.
sha_hex() {
  local out
  case $SHA_TOOL in
    sha256sum) out=$(sha256sum) ;;
    shasum) out=$(shasum -a 256) ;;
    openssl) out=$(openssl dgst -sha256); out=${out##*= } ;;
    *) die 4 "no sha256 tool (sha256sum, shasum or openssl) on PATH" ;;
  esac
  printf '%s' "${out%% *}"
}

# sha_str TEXT: sha256 hex of TEXT exactly (no trailing newline).
sha_str() { printf '%s' "$1" | sha_hex; }

# rand_hex BYTES: BYTES random bytes as lowercase hex.
rand_hex() {
  local h
  h=$(od -An -tx1 -N"$1" /dev/urandom | tr -d ' \n\t\r')
  [ ${#h} -eq $(( $1 * 2 )) ] || die 4 "could not read /dev/urandom"
  printf '%s' "$h"
}

# is_hex STRING LEN: true when STRING is exactly LEN lowercase hex chars.
is_hex() {
  [ ${#1} -eq "$2" ] || return 1
  case $1 in *[!0-9a-f]*) return 1 ;; esac
  return 0
}

# is_uint STRING: a decimal integer without leading zeros (or "0").
is_uint() {
  case $1 in ''|*[!0-9]*) return 1 ;; 0) return 0 ;; 0*) return 1 ;; esac
  [ ${#1} -le 6 ]
}

# chain_step X N: hash X forward N times (each step hashes the 64 hex chars).
chain_step() {
  local x=$1 i=0
  [ -n "$SHA_TOOL" ] || die 4 "no sha256 tool (sha256sum, shasum or openssl) on PATH"
  while [ "$i" -lt "$2" ]; do
    case $SHA_TOOL in
      sha256sum) x=$(printf '%s' "$x" | sha256sum) ;;
      shasum) x=$(printf '%s' "$x" | shasum -a 256) ;;
      *) x=$(printf '%s' "$x" | openssl dgst -sha256); x=${x##*= } ;;
    esac
    x=${x%% *}
    i=$(( i + 1 ))
  done
  printf '%s' "$x"
}

# Private state lives under $HOME/.claude/overmind (never in the binder).
ovm_dir() { printf '%s' "$HOME/.claude/overmind"; }
seed_file() { printf '%s/genesis-seed' "$(ovm_dir)"; }

# state_dir CID: the per-Collective private state dir. CID is 32 hex.
state_dir() {
  is_hex "$1" 32 || die 2 "collective-id must be 32 lowercase hex characters"
  printf '%s/collective/%s' "$(ovm_dir)" "$1"
}

# peer_ok NAME: a peer label is 1-100 printable chars, no tab, no pipe.
peer_ok() {
  [ -n "$1" ] && [ ${#1} -le 100 ] || return 1
  case $1 in *[[:cntrl:]]*|*'|'*) return 1 ;; esac
  return 0
}

# peer_key NAME: a path-safe key for a peer label.
peer_key() { sha_str "peer:$1" | cut -c1-16; }

# write_atomic FILE: write stdin to FILE through a temp file and mv.
write_atomic() {
  local f=$1 tmpf
  tmpf="$f.tmp.$$"
  ( set -C; cat > "$tmpf" ) || { rm -f "$tmpf"; return 1; }
  mv -f "$tmpf" "$f"
}

# seed_get KEY: the value of "KEY: value" in the seed file.
seed_get() {
  local f l
  f=$(seed_file)
  [ -f "$f" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%$'\r'}
    case $l in "$1: "*) printf '%s' "${l#"$1: "}"; return 0 ;; esac
  done < "$f"
  return 1
}

# kv_get FILE KEY: the value of "KEY: value" in FILE.
kv_get() {
  local l
  [ -f "$1" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%$'\r'}
    case $l in "$2: "*) printf '%s' "${l#"$2: "}"; return 0 ;; esac
  done < "$1"
  return 1
}

# membership_seed CID: M = sha256(seed-hex ":" cid).
membership_seed() {
  local s
  s=$(seed_get seed) || die 3 "no Genesis Seed: run genesis.sh mint first"
  is_hex "$s" 64 || die 3 "genesis-seed has a malformed seed: line"
  sha_str "$s:$1"
}

# chain_base CID G: X_0 of generation G = sha256(M ":" G).
chain_base() { sha_str "$(membership_seed "$1"):$2"; }

# anchor_of CID G: anchor_G = X_100.
anchor_of() { chain_step "$(chain_base "$1" "$2")" 100; }

# record CID G: the generation-G anchor record (three LF lines).
record() {
  local a n
  a=$(anchor_of "$1" "$2")
  n=$(sha_str "$(anchor_of "$1" $(( $2 + 1 )))")
  printf 'gen: %s\nanchor: %s\nnext: %s\n' "$2" "$a" "$n"
}

# parse_record: read a record on stdin (CR stripped, blank lines ignored)
# into REC_GEN REC_ANCHOR REC_NEXT. Fails unless exactly the three fields.
parse_record() {
  local l n=0
  REC_GEN="" REC_ANCHOR="" REC_NEXT=""
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%$'\r'}
    [ -z "$l" ] && continue
    n=$(( n + 1 ))
    case $n:$l in
      "1:gen: "*) REC_GEN=${l#gen: } ;;
      "2:anchor: "*) REC_ANCHOR=${l#anchor: } ;;
      "3:next: "*) REC_NEXT=${l#next: } ;;
      *) return 1 ;;
    esac
  done
  [ "$n" -eq 3 ] && is_uint "$REC_GEN" && [ "$REC_GEN" -ge 1 ] &&
    is_hex "$REC_ANCHOR" 64 && is_hex "$REC_NEXT" 64
}

# record_bytes: the canonical bytes of the parsed record.
record_bytes() { printf 'gen: %s\nanchor: %s\nnext: %s\n' "$REC_GEN" "$REC_ANCHOR" "$REC_NEXT"; }

# accepted_get DIR PEER: sets ACC_GEN ACC_INDEX ACC_VALUE ACC_NEXT ACC_STATUS
# from DIR/accepted (peer<TAB>gen<TAB>index<TAB>value<TAB>next<TAB>status).
accepted_get() {
  local f="$1/accepted" p g i v n s
  [ -f "$f" ] || return 1
  while IFS="$(printf '\t')" read -r p g i v n s || [ -n "$p" ]; do
    s=${s%$'\r'}
    if [ "$p" = "$2" ]; then
      ACC_GEN=$g ACC_INDEX=$i ACC_VALUE=$v ACC_NEXT=$n ACC_STATUS=$s
      return 0
    fi
  done < "$f"
  return 1
}

# accepted_put DIR PEER GEN INDEX VALUE NEXT STATUS: replace PEER's line.
accepted_put() {
  local f="$1/accepted" tab l
  tab=$(printf '\t')
  {
    if [ -f "$f" ]; then
      while IFS= read -r l || [ -n "$l" ]; do
        case $l in "$2$tab"*) ;; *) printf '%s\n' "$l" ;; esac
      done < "$f"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" "$7"
  } | write_atomic "$f"
}

# event DIR TEXT: append a dated line to DIR/events (controls stripped).
event() {
  local txt
  txt=$(printf '%s' "$2" | tr -d '\000-\037\177')
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$txt" >> "$1/events"
}

# Minute arithmetic on YYYYMMDDHHMM stamps, without date -d.
# days_from_civil Y M D: days since 1970-01-01 (proleptic Gregorian).
days_from_civil() {
  local y=$1 m=$2 d=$3 era yoe doy doe mp
  [ "$m" -le 2 ] && y=$(( y - 1 ))
  era=$(( (y >= 0 ? y : y - 399) / 400 ))
  yoe=$(( y - era * 400 ))
  if [ "$m" -gt 2 ]; then mp=$(( m - 3 )); else mp=$(( m + 9 )); fi
  doy=$(( (153 * mp + 2) / 5 + d - 1 ))
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  printf '%s' $(( era * 146097 + doe - 719468 ))
}

# civil_from_days DAYS: prints YYYYMMDD.
civil_from_days() {
  local z=$(( $1 + 719468 )) era doe yoe y doy mp d m
  era=$(( (z >= 0 ? z : z - 146096) / 146097 ))
  doe=$(( z - era * 146097 ))
  yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
  y=$(( yoe + era * 400 ))
  doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) ))
  mp=$(( (5 * doy + 2) / 153 ))
  d=$(( doy - (153 * mp + 2) / 5 + 1 ))
  if [ "$mp" -lt 10 ]; then m=$(( mp + 3 )); else m=$(( mp - 9 )); fi
  [ "$m" -le 2 ] && y=$(( y + 1 ))
  printf '%04d%02d%02d' "$y" "$m" "$d"
}

# stamp_ok YYYYMMDDHHMM: a plausible stamp.
stamp_ok() {
  case $1 in [12][0-9][0-9][0-9][01][0-9][0-3][0-9][0-2][0-9][0-5][0-9]) ;; *) return 1 ;; esac
  local mo=$(( 10#${1:4:2} )) d=$(( 10#${1:6:2} )) h=$(( 10#${1:8:2} ))
  [ "$mo" -ge 1 ] && [ "$mo" -le 12 ] && [ "$d" -ge 1 ] && [ "$d" -le 31 ] && [ "$h" -le 23 ]
}

# stamp_min YYYYMMDDHHMM: minutes since the epoch.
stamp_min() {
  local s=$1 days
  days=$(days_from_civil $(( 10#${s:0:4} )) $(( 10#${s:4:2} )) $(( 10#${s:6:2} )))
  printf '%s' $(( days * 1440 + 10#${s:8:2} * 60 + 10#${s:10:2} ))
}

# min_stamp MINUTES: back to YYYYMMDDHHMM.
min_stamp() {
  local m=$1 days rem
  days=$(( m / 1440 )); rem=$(( m % 1440 ))
  printf '%s%02d%02d' "$(civil_from_days "$days")" $(( rem / 60 )) $(( rem % 60 ))
}

# now_stamp: the local clock as YYYYMMDDHHMM.
now_stamp() { date +%Y%m%d%H%M; }

# post_stamp NAME: the YYYYMMDDHHMM of a post file name, or fail.
post_stamp() {
  local b=${1##*/} s
  case $b in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]-*) ;; *) return 1 ;; esac
  s="${b:0:8}${b:9:4}"
  stamp_ok "$s" || return 1
  printf '%s' "$s"
}
