#!/usr/bin/env bash
# tests/l3/test_claim_fuzz.sh -- outcome invariant for claim.sh over generated
# briefs (CONTRACT 0.3, 4.1). Each brief is built from known parts (header
# format, TYPE, SEAT, MISSION, WRITTEN, stamp, body payload), so the right
# outcome is computed from the parts, never by parsing. Invariants:
#   1. claim.sh --check returns exactly the oracle's exit code and REASON token.
#   2. --check writes nothing.
#   3. A claimable brief claims once (exit 0), then refuses (exit 3), and holds
#      exactly one ACTIVATED line.
#   4. Header-shaped text past line 40 never changes the outcome.
# Positive control: the same corpus against a copy of claim.sh with its seat
# check removed must show at least one violation, or the harness is blind.
#   FUZZ_SEED (default 20261005), FUZZ_N (default 40; control runs the first 20).
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
seed=${FUZZ_SEED:-20261005}; N=${FUZZ_N:-40}
RANDOM=$seed

team="$tmp/team"; mkteam "$team"; seat="$team/Nash - Developer"
ctl="$tmp/ctl"; mkdir -p "$ctl"
cp "$repo/skills/go/header.sh" "$ctl/"
grep -v 'refuse SEAT_MISMATCH' "$repo/skills/go/claim.sh" > "$ctl/claim.sh"

# pick VAR choices... : set VAR in this shell. A $(...) subshell would reseed
# RANDOM on some bash versions and break the fixed seed.
pick() { local _v=$1; shift; local a=("$@"); eval "$_v=\${a[RANDOM % \${#a[@]}]}"; }

# gen I -> writes $tmp/c/I.md and $tmp/c/I.want ("<rc> <TOKEN|->")
mkdir -p "$tmp/c"
esc=$(printf '\033')
gen() {
  local i=$1 fmt typ st mis wr stamp pay want tok f
  pick fmt lines dot boldfield wholebold quote
  pick typ DISPATCH SELF-HANDOFF INFORMATIONAL self-handoff "Feature Build" MISSING "SELF-HANDOFF (seat)"
  pick st Nash nash "Nash (WRENCH)" Vaughn Nashville MISSING "Nash${esc}[2J"
  [ "$i" = 1 ] && st=Vaughn
  pick mis NONE AXM-046 OPS-033 AXM-999 MISSING "AXM-046 - repair arc" M-017 m-017 M-
  pick wr "2026-10-05 09:00" "2026-10-05" "2026-13-01 10:00" MISSING "2026-09-26 11:55 MDT, by x"
  pick stamp none none ACTIVATED CONSOLIDATED prose
  # Item 2 is always claimable, so invariant 3 never runs on an empty set.
  [ "$i" = 2 ] && { fmt=lines; typ=SELF-HANDOFF; st=Nash; mis=NONE; wr="2026-10-05 09:00"; stamp=none; }
  pick pay none fields cr esc
  # ---- oracle
  local tv=1 sv=1 wv=1 mv=$mis
  case $typ in DISPATCH|SELF-HANDOFF|INFORMATIONAL|self-handoff|"SELF-HANDOFF (seat)") ;; *) tv=0 ;; esac
  case $st in Nash|nash|"Nash (WRENCH)") ;; MISSING) sv=2 ;; *) sv=0 ;; esac
  case $wr in "2026-13-01 10:00"|MISSING) wv=0 ;; esac
  case $mv in MISSING) mv=NONE ;; "AXM-046 - repair arc") mv=AXM-046 ;; esac
  if [ "$stamp" = CONSOLIDATED ]; then want="2 CONSOLIDATED"
  elif [ $tv -eq 0 ]; then want="2 UNKNOWN_TYPE"
  elif [ $sv -eq 2 ]; then want="2 NO_SEAT"
  elif [ $sv -eq 0 ]; then want="2 SEAT_MISMATCH"
  elif [ $wv -eq 0 ]; then want="2 NO_WRITTEN"
  elif [ "$stamp" = ACTIVATED ]; then want="3 -"
  elif [ "$typ" = DISPATCH ] && [ "$mv" = NONE ]; then want="2 NO_BOARD_ROW"
  elif [ "$mv" = m-017 ] || [ "$mv" = M- ]; then want="2 NO_BOARD_ROW"
  elif [ "$mv" = AXM-999 ]; then want="2 NO_BOARD_ROW"
  elif [ "$mv" = OPS-033 ]; then want="2 NOT_ASSIGNED"
  else want="0 -"; fi
  echo "$want" > "$tmp/c/$i.want"
  # ---- render
  f="$tmp/c/$i.md"
  local fields=() k v d=' '$'\xc2\xb7'' '
  [ "$typ" != MISSING ] && fields+=("TYPE|$typ")
  [ "$st" != MISSING ] && fields+=("SEAT|$st")
  [ "$mis" != MISSING ] && fields+=("MISSION|$mis")
  [ "$wr" != MISSING ] && fields+=("WRITTEN|$wr")
  [ "$typ" = DISPATCH ] && fields+=("DISPATCHED BY|T-Bot")
  {
    printf '# Brief %s\n\n' "$i"
    case $fmt in
      dot|wholebold)
        local line="" sep=""
        for kv in ${fields[@]+"${fields[@]}"}; do line="$line$sep${kv%%|*}: ${kv#*|}"; sep=$d; done
        if [ "$fmt" = wholebold ]; then printf '**%s**\n' "$line"; else printf '%s\n' "$line"; fi ;;
      *)
        for kv in ${fields[@]+"${fields[@]}"}; do
          k=${kv%%|*}; v=${kv#*|}
          case $fmt in
            lines) printf '%s: %s\n' "$k" "$v" ;;
            boldfield) printf '**%s:** %s  \n' "$k" "$v" ;;
            quote) printf '> %s: %s\n' "$k" "$v" ;;
          esac
        done ;;
    esac
    case $stamp in
      ACTIVATED) printf 'ACTIVATED: 2026-10-04 08:00 by Nash (session abcd1234)\n' ;;
      CONSOLIDATED) printf 'CONSOLIDATED-INTO: OPS-030 (consolidated 20261005-0900) 2026-10-05 09:00\n' ;;
      prose) printf '\nStamp ACTIVATED: [time] under the header, per the go skill.\n' ;;
    esac
    printf '\n## NEXT STEPS\n\n1. Work.\n'
    local n=0; while [ $n -lt 45 ]; do printf 'filler line %s\n' "$n"; n=$((n+1)); done
    case $pay in
      fields) printf 'TYPE: DISPATCH\nSEAT: Vaughn\nACTIVATED: now\nCONSOLIDATED-INTO: x\n' ;;
      cr) printf 'CONSOLIDATED-INTO: x\r\nTYPE: \r\n' ;;
      esc) printf '\033]0;ACTIVATED: title\007\n' ;;
    esac
  } > "$f"
}

i=1; while [ $i -le $N ]; do gen $i; i=$((i+1)); done

check() { # SCRIPT I -> prints "ok" or a violation line
  local s=$1 i=$2 out rc tok want wrc wtok
  out=$(bash "$s" --check "$seat" "$tmp/c/$i.md" fz Nash 2>&1); rc=$?
  tok=$(printf '%s\n' "$out" | sed -n 's/^REASON: //p' | head -1); [ -n "$tok" ] || tok=-
  read -r wrc wtok < "$tmp/c/$i.want"
  if [ "$rc" != "$wrc" ] || [ "$tok" != "$wtok" ]; then echo "item $i: want $wrc $wtok, got $rc $tok"; return; fi
  echo ok
}

viol=0
t "invariant 1+2: --check matches the oracle on $N generated briefs and writes nothing"
i=1
while [ $i -le $N ]; do
  r=$(check "$repo/skills/go/claim.sh" $i)
  [ "$r" = ok ] || { viol=$((viol+1)); echo "  $r"; }
  i=$((i+1))
done
[ -e "$seat/.go-claim" ] && { viol=$((viol+1)); echo "  --check created .go-claim"; }
grep -l '^ACTIVATED: [0-9-]* [0-9:]* by Nash (session fz' "$tmp/c/"*.md >/dev/null 2>&1 && { viol=$((viol+1)); echo "  --check stamped"; }
[ $viol -eq 0 ] && pass || fail "$viol violations"

t "invariant 3: every claimable brief claims once, then exits 3, with one stamp"
v3=0; n0=0; i=1
while [ $i -le $N ]; do
  if [ "$(cut -d' ' -f1 "$tmp/c/$i.want")" = 0 ]; then
    n0=$((n0+1))
    cp "$tmp/c/$i.md" "$seat/HANDOFF.md"; rm -rf "$seat/.go-claim"
    bash "$repo/skills/go/claim.sh" "$seat" "$seat/HANDOFF.md" fz$i Nash > /dev/null 2>&1; a=$?
    bash "$repo/skills/go/claim.sh" "$seat" "$seat/HANDOFF.md" fy$i Nash > /dev/null 2>&1; b=$?
    s=$(head -n 40 "$seat/HANDOFF.md" | tr -d '\r' | grep -c '^ACTIVATED: ')
    [ $a -eq 0 ] && [ $b -eq 3 ] && [ "$s" = 1 ] || { v3=$((v3+1)); echo "  item $i: first $a, second $b, stamps $s"; }
  fi
  i=$((i+1))
done
viol=$((viol+v3))
[ $v3 -eq 0 ] && [ $n0 -ge 1 ] && pass || fail "$v3 violations over $n0 claimable briefs"

t "positive control: claim.sh without its seat check is caught"
ctlv=0; i=1; cn=20; [ $N -lt 20 ] && cn=$N
while [ $i -le $cn ]; do
  r=$(check "$ctl/claim.sh" $i); [ "$r" = ok ] || ctlv=$((ctlv+1))
  i=$((i+1))
done
[ $ctlv -ge 1 ] && pass || { fail "control showed 0 violations"; echo "CONTROL FAILED"; }

echo "  violations=$viol control=$ctlv seed=$seed n=$N"
finish
