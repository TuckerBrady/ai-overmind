#!/usr/bin/env bash
# L2 2.12 (CONSOLIDATE_BRIEF step 8): TARS heartbeats this session's own
# _claims/<M>.<sid> files and reports a fresh same-seat claim on the same
# mission once per (M, other sid). It writes nothing else in the team tree.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

root="$tmp/team"; mkteam "$root"
dev="$root/Nash - Developer"; cl="$root/_claims"
mkdir -p "$cl"
me=sessA
printf '100 Nash\n' > "$cl/AXM-1.$me"
printf '100 Nash\n' > "$cl/OPS-30a.$me"
printf '4880 Nash\n' > "$cl/AXM-1.sessB"      # same seat, fresh
printf '4990 Vaughn\n' > "$cl/AXM-1.sessC"    # other seat
printf '1000 Nash\n' > "$cl/OPS-30a.sessD"    # same seat, stale (> 1800 s)
printf '4990 Nash\n' > "$cl/AXM-2.sessE"      # a mission this session doesn't hold
printf '100 Nash\n' > "$cl/lower-1.$me"       # bad mission name
printf '100 Nash\n' > "$root/x.y"             # outside _claims (the ../x.y case)
printf '100 Nash\n' > "$cl/AXM-3.$me.extra"   # not <M>.<sid>
unreach=0
if ( : > "$cl/AXM-1.$cr" ) 2>/dev/null && [ -f "$cl/AXM-1.$cr" ]; then
  printf '100 Nash\n' > "$cl/AXM-1.$cr"; crcase=1
else
  echo "  unreachable on this FS: _claims/AXM-1.<CR>"; unreach=$(( unreach + 1 )); crcase=""
fi

# snapshot: everything old, then list what is newer afterwards
find "$root" -exec touch -t 200001010000 {} +
: > "$tmp/ref"; touch -t 200101010000 "$tmp/ref"
before=$(find "$root" -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done)

all=""
for n in 0 1 2; do
  out=$(TARS_NOW=$(( 5000 + n * 100 )) hook "$me" "$dev")
  all+="$out"$'\n'
  read -r ep rest < "$cl/AXM-1.$me"
  t "2.12 own claim epoch advances (turn $n)"
  expect "epoch=$ep" test "$ep" = $(( 5000 + n * 100 ))
done
t "2.12 the seat field is kept"
expect "content: $(cat "$cl/AXM-1.$me")" test "$(cat "$cl/AXM-1.$me")" = "5200 Nash"
t "2.12 a fresh same-seat foreign claim: exactly one L11 across 3 turns"
expect "got: $all" test "$(count 'TARS: another session also holds AXM-1 (last active 2 min ago). /consolidate folds it in.' "$all")" = 1
t "2.12 cross-seat, stale and unheld missions are silent"
expect "got: $all" test "$(count 'another session' "$all")" = 1

t "2.12 bad names are ignored and unmodified"
expect "lower-1 changed" test "$(cat "$cl/lower-1.$me")" = "100 Nash"
t "2.12 ../x.y is unmodified"
expect "x.y changed" test "$(cat "$root/x.y")" = "100 Nash"
t "2.12 <M>.<sid>.extra is unmodified"
expect "extra changed" test "$(cat "$cl/AXM-3.$me.extra")" = "100 Nash"
if [ -n "$crcase" ]; then
  t "2.12 AXM-1.<CR> is unmodified"
  expect "CR file changed" test "$(cat "$cl/AXM-1.$cr")" = "100 Nash"
fi
t "2.12 foreign claims are not heartbeated"
expect "sessB changed" test "$(cat "$cl/AXM-1.sessB")" = "4880 Nash"

after=$(find "$root" -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done)
changed=$(find "$root" -newer "$tmp/ref" | LC_ALL=C sort)
want=$(printf '%s\n' "$cl/AXM-1.$me" "$cl/OPS-30a.$me" | LC_ALL=C sort)
t "2.12 the team tree changes only in _claims/*.<own sid>"
expect "changed: $changed" test "$changed" = "$want"
t "2.12 no file appears or disappears in the team tree"
expect "file list differs" test "$(printf '%s\n' "$before" | cut -d' ' -f1)" = "$(printf '%s\n' "$after" | cut -d' ' -f1)"

# ---- TARS_CLAIM_FRESH_SEC, symlinks
out=$(TARS_CLAIM_FRESH_SEC=60 TARS_NOW=5300 hook sessF "$dev")
printf '5290 Nash\n' > "$cl/AXM-1.sessF"
out=$(TARS_CLAIM_FRESH_SEC=60 TARS_NOW=5300 hook sessF "$dev")
t "2.12 TARS_CLAIM_FRESH_SEC narrows freshness"
expect "got: $out" test "$(count 'another session' "$out")" = 0

printf '100 Nash\n' > "$tmp/outside"
ln -s "$tmp/outside" "$cl/AXM-7.$me" 2>/dev/null
if [ -L "$cl/AXM-7.$me" ]; then
  TARS_NOW=5400 hook "$me" "$dev" >/dev/null
  t "2.12 a symlinked own claim is never written through"
  expect "outside changed" test "$(cat "$tmp/outside")" = "100 Nash"
else
  rm -f "$cl/AXM-7.$me"
  echo "  unreachable on this FS: symlinked claim"; unreach=$(( unreach + 1 ))
fi

t "grammar"
expect "grammar" grammar_ok "$all"
echo "  unreachable=$unreach"
finish
