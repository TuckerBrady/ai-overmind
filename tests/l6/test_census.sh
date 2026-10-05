#!/usr/bin/env bash
# L6 6.10 / GAP-46 / RUBRIC L6.5: the CLI-fallback census, 4-argument form.
# Lists only this seat's _claims/<ID>.* and the JSONL transcripts that name the
# ID and changed in the last 7 days. Another seat's claim is never listed.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l6}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
census="$repo/skills/consolidate/census.sh"
SB=${BASH:-bash}

root="$tmp/team"; cl="$root/_claims"; mkdir -p "$cl" "$root/T-Bot - The Overmind"
: > "$root/MISSION_BOARD.md"
printf '1791100000 T-Bot\n' > "$cl/AXM-046.local_f8d87694"     # same seat: listed
printf '1791100100 T-Bot\n' > "$cl/AXM-046.local_2f9e3e12"     # same seat: listed
printf '1791100200 Vaughn\n' > "$cl/AXM-046.local_aaaa1111"    # another seat: never listed
printf '1791100300 T-Bot Junior\n' > "$cl/AXM-046.local_bbbb2222" # a seat whose name only starts the same
printf '1791100400 T-Bot\n' > "$cl/AXM-0466.local_cccc3333"    # another mission sharing a prefix
printf '1791100500 T-Bot\n' > "$cl/AXM-047.local_dddd4444"     # another mission
printf 'garbage\n' > "$cl/AXM-046.local_eeee5555"              # no epoch
printf '1791100600 T-Bot\n' > "$cl/AXM-046.bad;sid"            # sid outside the 7.3 class
printf '1791100700 T-Bot\n' > "$root/AXM-046.local_ffff6666"   # outside _claims

proj="$tmp/projects"; seatdir="$proj/C--team-T-Bot---The-Overmind"; mkdir -p "$seatdir/sub/subagents"
rec() { printf '{"type":"user","cwd":"C:\\\\team\\\\T-Bot - The Overmind","message":{"role":"user","content":"%s"}}\n' "$1"; }
rec 'start AXM-046 audit'        > "$seatdir/11111111-aaaa-4aaa-8aaa-111111111111.jsonl"   # listed
rec 'HANDOFF-AXM-046.md written' > "$seatdir/22222222-aaaa-4aaa-8aaa-222222222222.jsonl"   # listed
rec 'AXM-046 long ago'           > "$seatdir/33333333-aaaa-4aaa-8aaa-333333333333.jsonl"   # too old
rec 'AXM-0466 is different'      > "$seatdir/44444444-aaaa-4aaa-8aaa-444444444444.jsonl"   # not the ID
rec 'nothing relevant'           > "$seatdir/55555555-aaaa-4aaa-8aaa-555555555555.jsonl"   # no ID
rec 'AXM-046 in a subagent'      > "$seatdir/sub/subagents/agent-1.jsonl"                   # not a session
rec 'AXM-046 at the top level'   > "$proj/66666666-aaaa-4aaa-8aaa-666666666666.jsonl"      # listed
touch -t 202001010000 "$seatdir/33333333-aaaa-4aaa-8aaa-333333333333.jsonl"

out=$("$SB" "$census" "$root" AXM-046 "$proj" T-Bot); rc=$?

t "exit 0"
[ "$rc" = 0 ] && pass || fail "rc=$rc"
t "lists exactly this seat's claims on the ID"
got=$(printf '%s\n' "$out" | LC_ALL=C awk -F '\t' '$1 == "claim" { print $2 }' | sort | tr '\n' ' ')
[ "$got" = "local_2f9e3e12 local_f8d87694 " ] && pass || fail "got: $got"
t "a claim held by another seat is absent from the output"
printf '%s\n' "$out" | LC_ALL=C grep -qE 'aaaa1111|bbbb2222|Vaughn' && fail "foreign claim listed" || pass
t "claim rows carry the epoch and the path"
printf '%s\n' "$out" | LC_ALL=C grep -q "^claim	local_f8d87694	1791100000	$cl/AXM-046.local_f8d87694\$" && pass || fail "$(printf '%s\n' "$out" | grep f8d8)"
t "lists exactly the recent session transcripts that name the ID"
got=$(printf '%s\n' "$out" | LC_ALL=C awk -F '\t' '$1 == "transcript" { print substr($2, 1, 8) }' | sort | tr '\n' ' ')
[ "$got" = "11111111 22222222 66666666 " ] && pass || fail "got: $got"
t "transcript rows carry the recorded cwd"
printf '%s\n' "$out" | LC_ALL=C grep -qF "transcript	11111111-aaaa-4aaa-8aaa-111111111111	C:\\team\\T-Bot - The Overmind	" && pass || fail "$(printf '%s\n' "$out" | grep 11111111)"
t "nothing else is listed"
n=$(printf '%s\n' "$out" | LC_ALL=C grep -c .)
[ "$n" = 5 ] && pass || fail "$n rows"

t "another seat sees only its own claim"
o2=$("$SB" "$census" "$root" AXM-046 "$proj" Vaughn | LC_ALL=C awk -F '\t' '$1 == "claim" { print $2 }' | tr '\n' ' ')
[ "$o2" = "local_aaaa1111 " ] && pass || fail "got: $o2"

t "a symlinked _claims is refused"
root2="$tmp/team2"; mkdir -p "$root2"
if ln -s "$cl" "$root2/_claims" 2>/dev/null && [ -L "$root2/_claims" ]; then
  o3=$("$SB" "$census" "$root2" AXM-046 "$tmp/none" T-Bot)
  [ -z "$o3" ] && pass || fail "listed through a symlink: $o3"
else
  echo "  not reachable on this FS: symlinked _claims"; pass
fi

t "a control byte in a transcript's cwd is stripped"
printf '{"cwd":"C:\\\\x%sy","m":"AXM-046"}\n' $'\033' > "$seatdir/77777777-aaaa-4aaa-8aaa-777777777777.jsonl"
o4=$("$SB" "$census" "$root" AXM-046 "$proj" T-Bot | LC_ALL=C grep 77777777)
printf '%s' "$o4" | LC_ALL=C grep -q $'\033' && fail "ESC in output" || pass

t "a bad ID, a missing argument or an empty seat exits 2"
"$SB" "$census" "$root" 'AXM-0;rm' "$proj" T-Bot > /dev/null 2>&1; a=$?
"$SB" "$census" "$root" AXM-046 "$proj" > /dev/null 2>&1; b=$?
"$SB" "$census" "$root" AXM-046 "$proj" '' > /dev/null 2>&1; c=$?
"$SB" "$census" "$root" 'AXM-046.*' "$proj" T-Bot > /dev/null 2>&1; d=$?
[ "$a$b$c$d" = 2222 ] && pass || fail "got $a $b $c $d"

t "A-17: a single-letter mission M-017 is accepted and found"
printf '1791100800 T-Bot\n' > "$cl/M-017.local_99998888"
rec 'dispatching M-017 now' > "$seatdir/88888888-aaaa-4aaa-8aaa-888888888888.jsonl"
o5=$("$SB" "$census" "$root" M-017 "$proj" T-Bot); r5=$?
[ "$r5" = 0 ] && printf '%s\n' "$o5" | LC_ALL=C grep -q '^claim	local_99998888	' &&
  printf '%s\n' "$o5" | LC_ALL=C grep -q '^transcript	88888888-' && pass || fail "rc=$r5 out=$o5"

t "A-17: m-017, -17 and M- are rejected"
"$SB" "$census" "$root" m-017 "$proj" T-Bot > /dev/null 2>&1; a=$?
"$SB" "$census" "$root" -17 "$proj" T-Bot > /dev/null 2>&1; b=$?
"$SB" "$census" "$root" M- "$proj" T-Bot > /dev/null 2>&1; c=$?
[ "$a$b$c" = 222 ] && pass || fail "got $a $b $c"

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
