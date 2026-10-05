#!/usr/bin/env bash
# skills/collective/lib.sh: shared helpers for the Collective scripts
# (proof.sh, state.sh, catchup.sh, post-name.sh, and ../assimilate/identity.sh).
# Sourced, never run. Formats are in reference/collective.md "Formats".
#
# Identity is one ed25519 key per Overmind, used through `ssh-keygen -Y
# sign|verify` (OpenSSH 8.1 or later). Peers' public keys are pinned in this
# Overmind's private state only after an out-of-band fingerprint check and the
# human's yes (CONTRACT A-23).
#
# Portability (CONTRACT 0.4, GAP-12): POSIX utilities plus ssh-keygen and git.
# Random via od -An -tx1 -N<n> /dev/urandom. No stat, no date -d, no sed -i,
# no jq. Runs under bash 3.2 and 5.x.

NAMESPACE=ai-overmind-collective

# die CODE MESSAGE: print to stderr and exit.
die() { printf '%s\n' "$2" >&2; exit "$1"; }

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

# Private state lives under $HOME/.claude/overmind/collective (never in a binder).
coll_dir() { printf '%s/.claude/overmind/collective' "$HOME"; }
key_file() { printf '%s/id_ed25519' "$(coll_dir)"; }

# state_dir CID: the per-Collective private state dir. CID is 32 hex.
state_dir() {
  is_hex "$1" 32 || die 2 "collective-id must be 32 lowercase hex characters"
  printf '%s/%s' "$(coll_dir)" "$1"
}

# label_ok LABEL: 1-100 ASCII letters, digits, space and . _ ( ) , -
# Anything else (another script's lookalike letters, a pipe, a control
# character) is refused, so two labels can only collide in plain ASCII.
label_ok() {
  [ -n "$1" ] && [ ${#1} -le 100 ] || return 1
  case $1 in *[!A-Za-z0-9\ ._\(\),-]*) return 1 ;; esac
  [ -n "$(label_norm "$1")" ]
}

# label_norm LABEL: case-folded, punctuation and spaces stripped (N5). Labels
# are compared, and signed, in this form.
label_norm() { printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -cd 'a-z0-9'; }

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

# write_atomic FILE: write stdin to FILE through a temp file and mv.
write_atomic() {
  local f=$1 tmpf
  tmpf="$f.tmp.$$"
  ( set -C; cat > "$tmpf" ) || { rm -f "$tmpf"; return 1; }
  mv -f "$tmpf" "$f"
}

# event DIR TEXT: append a dated line to DIR/events (controls stripped).
event() {
  local txt
  txt=$(printf '%s' "$2" | tr -d '\000-\037\177')
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$txt" >> "$1/events"
}

# have_sshsig: ssh-keygen can really sign and verify (-Y, OpenSSH 8.1+).
# A round trip with a throwaway key, not a version string.
have_sshsig() {
  local t rc=1
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  t=$(mktemp -d "${TMPDIR:-/tmp}/ovmsig.XXXXXX") || return 1
  if ssh-keygen -q -t ed25519 -N "" -C probe -f "$t/k" </dev/null >/dev/null 2>&1 &&
     printf 'probe' > "$t/m" &&
     ssh-keygen -Y sign -f "$t/k" -n "$NAMESPACE" "$t/m" >/dev/null 2>&1 &&
     printf 'probe %s
' "$(key_body "$t/k.pub")" > "$t/as" &&
     ssh-keygen -Y verify -f "$t/as" -I probe -n "$NAMESPACE" -s "$t/m.sig" < "$t/m" >/dev/null 2>&1; then
    rc=0
  fi
  rm -rf "$t"
  return "$rc"
}

# fingerprint PUBFILE: the SHA256: fingerprint of a public key.
fingerprint() {
  local o
  o=$(ssh-keygen -lf "$1" 2>/dev/null) || return 1
  o=${o#* }; o=${o%% *}
  case $o in SHA256:*) printf '%s' "$o" ;; *) return 1 ;; esac
}

# pubkey_ok FILE: exactly one ssh-ed25519 public key line.
pubkey_ok() {
  local l n=0 t
  [ -f "$1" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%$'\r'}
    [ -z "$l" ] && continue
    n=$(( n + 1 ))
    t=${l%% *}
    [ "$t" = ssh-ed25519 ] || return 1
  done < "$1"
  [ "$n" -eq 1 ] && fingerprint "$1" >/dev/null
}

# key_body FILE: "ssh-ed25519 <base64>" (comment dropped).
key_body() { tr -d '\r' < "$1" | grep -v '^$' | head -1 | cut -d' ' -f1,2; }

# allowed_signers CID: rebuild <cid>/allowed_signers from the pins. Each line
# names the normalized label as principal and allows the git and Collective
# namespaces only.
allowed_signers() {
  local d p n
  d=$(state_dir "$1") || return 2
  {
    for p in "$d"/pins/*.pub; do
      [ -f "$p" ] || continue
      n=${p##*/}; n=${n%.pub}
      printf '%s namespaces="git,%s" %s\n' "$n" "$NAMESPACE" "$(key_body "$p")"
    done
  } | write_atomic "$d/allowed_signers"
}

# commit_signer REPO CID SHA: print the pinned label whose key signed SHA, or
# fail. GitHub's verified flag and logins play no part (A-23). Only an SSH
# signature can verify: the OpenPGP and X.509 programs are set to `false`, so
# a gpg-signed commit (whose UID text is attacker-chosen) always fails (MF-1).
# The signer is read only from a line that BEGINS with the ssh-keygen verdict,
# and it must name an existing pin.
commit_signer() {
  local d out l who=""
  d=$(state_dir "$2") || return 2
  [ -s "$d/allowed_signers" ] || return 1
  out=$(git -C "$1" -c gpg.format=ssh -c gpg.openpgp.program=false -c gpg.x509.program=false \
        -c gpg.ssh.program=ssh-keygen -c gpg.ssh.allowedSignersFile="$d/allowed_signers" \
        verify-commit "$3" 2>&1) || return 1
  while IFS= read -r l; do
    l=${l%$'\r'}
    case $l in
      'Good "git" signature for '*) who=${l#Good \"git\" signature for }; who=${who%% *}; break ;;
    esac
  done <<EOF
$out
EOF
  [ -n "$who" ] && [ -f "$d/pins/$who.pub" ] || return 1
  printf '%s' "$who"
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
