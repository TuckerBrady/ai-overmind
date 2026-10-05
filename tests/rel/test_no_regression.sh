#!/usr/bin/env bash
# tests/rel/test_no_regression.sh -- the permanent invariant (AMENDMENTS A-44):
# no regression against the live guard. Every command that fb649ac's
# hooks/twin-guard.sh (read from git by blob id) denies to a twin, HEAD's guard
# must deny too.
#
# Corpus: the REL r4 grader's commands (fixtures/regr_seed.txt), the
# comment-dot command, and generated combinations of
#   write verb x protected target x substitution shape
# (backticks, $( ), quoted backticks, a substitution beside the target).
# Prints regressions=<n>; passes only at 0. Deliberate, ruled relaxations
# (a quoted " . " is not source, round 2; an over-cap main session passes, A-33
# round 2) are outside this corpus: they are main-session or concatenation
# cases, not twin writes.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

old_blob=57b7dd93353690875b540dece15ee318408bd1d8   # fb649ac:hooks/twin-guard.sh
OLD="$tmp/guard-fb649ac.sh"
t "fb649ac's guard is readable from git by blob id"
if git -C "$repo" cat-file blob "$old_blob" > "$OLD" 2>/dev/null && [ -s "$OLD" ]; then pass
else echo "  cannot read blob $old_blob (needs fetch-depth: 0)"; fail "old guard"; finish; exit 1; fi

# A seat with protected files around it and no team root in reach, so only the
# pre-check runs (the invariant is about what each guard denies).
seat="$tmp/t/Seat"; mkdir -p "$seat" "$tmp/t/Other" "$tmp/t/_Team" "$seat/_claims" "$seat/.go-claim/a"
for f in INBOX.md BOOT.md HANDOFF.md list x; do printf 'x\n' > "$seat/$f"; done
printf 'x\n' > "$tmp/t/Other/INBOX.md"; printf 'x\n' > "$tmp/t/_Team/team.db"

verdict() { # GUARD CMD -> deny | allow
  local r
  r=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","agent_id":"nr","agent_type":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"nr1"}' \
    "$(js "$seat")" "$TWIN" "$(js "$2")" | TMPDIR="$tmp/snaps" "$B" "$1" 2>/dev/null)
  case $r in *'"permissionDecision":"deny"'*) echo deny ;; *) echo allow ;; esac
}

corpus=()
while IFS= read -r c || [ -n "$c" ]; do [ -n "$c" ] && corpus+=("$c"); done < "$here/fixtures/regr_seed.txt"
corpus+=("echo 1 # it's"$'\n'". ./x.sh"$'\n'"echo 2 # '")
verbs=("rm -f" "touch" "truncate -s0" "chmod 000" "unlink" "shred -u" "cp x" "mv x" "ln -sf x" "install x" "rsync x" "tee" "tee -a" "sed -i s/a/b/" "perl -pi -e s/a/b/" ">" ">>")
targets=("INBOX.md" "../Other/INBOX.md" "../_Team/team.db")
for v in "${verbs[@]}"; do
  for tg in "${targets[@]}"; do
    for shape in plain bt dollar qbt beside; do
      case $shape in
        plain) a=$tg ;;
        bt) a="\`grep -l . $tg\`" ;;
        dollar) a="\$(grep -l . $tg)" ;;
        qbt) a="\"\`ls $tg\`\"" ;;
        beside) a="\`cat list\` $tg" ;;
      esac
      case $v in
        '>'|'>>') corpus+=("echo x $v $a") ;;
        tee|'tee -a') corpus+=("echo x | $v $a") ;;
        *) corpus+=("$v $a") ;;
      esac
    done
  done
done

t "regressions against fb649ac's guard over ${#corpus[@]} commands"
n=0 od=0 nd=0 reg=0 list=""
for c in "${corpus[@]}"; do
  n=$((n + 1))
  vo=$(verdict "$OLD" "$c")
  [ "$vo" = deny ] || continue
  od=$((od + 1))
  vn=$(verdict "$GUARD" "$c")
  if [ "$vn" = deny ]; then nd=$((nd + 1)); else reg=$((reg + 1)); list="$list
    allowed now: ${c//$'\n'/ \\n }"; fi
done
echo "  corpus=$n fb649ac-denied=$od head-denied-of-those=$nd"
echo "  regressions=$reg"
[ -n "$list" ] && printf '%s\n' "$list"
[ "$n" -ge 200 ] || fail "corpus only $n commands"
[ $reg -eq 0 ] && pass || fail "regressions=$reg"

finish
