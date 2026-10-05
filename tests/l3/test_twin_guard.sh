#!/usr/bin/env bash
# tests/l3/test_twin_guard.sh -- hooks/twin-guard.sh, the PreToolUse guard that
# stops splinter twins writing team state (CONTRACT 4.9, 7.8; finding FW-25).
# RUBRIC L3.8. The matrix: 8 protected targets x {Write, Edit, Bash redirect}
# denied for a twin and allowed for anyone else; reads allowed; a deliverable
# allowed. Then generated combinations of path spellings and write commands.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

work="$tmp/team/Nash - Developer"; mkdir -p "$work" "$tmp/team/_claims"
: > "$work/INBOX.md"
TWIN='ai-overmind:splinter-twin'

js() { # JSON-escape a string
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}
  printf '%s' "$s"
}
# hook AGENT TOOL INPUT_JSON -> the guard's verdict: deny | allow | BAD:<output>
hook() {
  local a="" out rc
  [ -n "$1" ] && a=",\"agent_id\":\"a1\",\"agent_type\":\"$(js "$1")\""
  out=$(printf '{"session_id":"s1","transcript_path":"/x.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"PreToolUse"%s,"tool_name":"%s","tool_input":%s,"tool_use_id":"t1"}' \
        "$(js "$work")" "$a" "$2" "$3" | bash "$GUARD" 2>&1); rc=$?
  if [ $rc -ne 0 ]; then echo "BAD:rc=$rc"; return; fi
  case $out in
    '') echo allow ;;
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'*'"}}') echo deny ;;
    *) echo "BAD:$out" ;;
  esac
}
write_in() { printf '{"file_path":"%s","content":"x"}' "$(js "$1")"; }
edit_in() { printf '{"file_path":"%s","old_string":"a","new_string":"b"}' "$(js "$1")"; }
bash_in() { printf '{"command":"%s","description":"d"}' "$(js "$1")"; }
expect() { # want got label
  [ "$1" = "$2" ] || { fail "$3: want $1, got $2"; return 1; }
}

targets=("INBOX.md" "HANDOFF.md" "HANDOFF-AXM-1.md" "mission-complete-AXM-1.md" "GOPHER_REGISTRY.md" "MISSION_BOARD.md" "_Team/team.db" "_claims/AXM-1.s1")

t "matrix: 8 protected targets x {Write, Edit, Bash redirect} denied for a twin"
bad=0
for tg in "${targets[@]}"; do
  p="$work/$tg"
  expect deny "$(hook "$TWIN" Write "$(write_in "$p")")" "Write $tg" || bad=1
  expect deny "$(hook "$TWIN" Edit "$(edit_in "$p")")" "Edit $tg" || bad=1
  expect deny "$(hook "$TWIN" Bash "$(bash_in "echo note >> \"$p\"")")" "Bash >> $tg" || bad=1
done
[ $bad -eq 0 ] && pass

t "matrix: the same 24 calls are allowed for a main-thread session and for another agent type"
bad=0
for tg in "${targets[@]}"; do
  p="$work/$tg"
  for ag in "" Explore; do
    expect allow "$(hook "$ag" Write "$(write_in "$p")")" "[$ag] Write $tg" || bad=1
    expect allow "$(hook "$ag" Edit "$(edit_in "$p")")" "[$ag] Edit $tg" || bad=1
    expect allow "$(hook "$ag" Bash "$(bash_in "echo note >> \"$p\"")")" "[$ag] Bash $tg" || bad=1
  done
done
[ $bad -eq 0 ] && pass

t "reads are always allowed for a twin"
bad=0
for c in "cat \"$work/INBOX.md\"" "grep -n UNREAD INBOX.md" "head -40 HANDOFF.md" "cat INBOX.md > /tmp/copy.txt" \
         "cat INBOX.md 2>/dev/null | wc -l" "python ../_Team/team.py board mine Nash" "python ../_Team/team.py gopher show" \
         "bash skills/go/claim.sh --check . ./HANDOFF.md s1 Nash" "awk '/UNREAD/' INBOX.md" "cp HANDOFF.md /tmp/brief.md"; do
  expect allow "$(hook "$TWIN" Bash "$(bash_in "$c")")" "read: $c" || bad=1
done
expect allow "$(hook "$TWIN" Read "$(printf '{"file_path":"%s"}' "$(js "$work/INBOX.md")")")" "Read tool" || bad=1
[ $bad -eq 0 ] && pass

t "a twin's deliverables are allowed"
bad=0
expect allow "$(hook "$TWIN" Write "$(write_in "$work/drafts/SPEC_TWIN.md")")" "Write deliverable" || bad=1
expect allow "$(hook "$TWIN" Edit "$(edit_in "$tmp/repo/src/main.go")")" "Edit deliverable" || bad=1
expect allow "$(hook "$TWIN" Bash "$(bash_in "echo done > report.md && git add report.md")")" "Bash deliverable" || bad=1
expect allow "$(hook "$TWIN" Write "$(write_in "$work/INBOX.md.bak/notes.md")")" "a folder named like a protected file" || bad=1
[ $bad -eq 0 ] && pass

# ---------------------------------------------------------------- generated combinations
# Every spelling of every protected name, through every write form, is denied
# for a twin and allowed for the main thread. Spellings: as-is, lower case,
# Windows backslashes, quoted path with spaces, NTFS trailing dot, NTFS stream.
t "generated: spellings x write forms, denied for a twin, allowed otherwise"
# Three seeded forms per (name, spelling) by default; GUARD_FULL=1 runs all 13.
RANDOM=${FUZZ_SEED:-20261005}
names=("INBOX.md" "HANDOFF.md" "HANDOFF-OPS-9.md" "mission-complete.md" "mission-complete-OPS-9.md" "GOPHER_REGISTRY.md" "MISSION_BOARD.md" "team.db")
spell() { # form name -> path
  case $1 in
    plain) printf '%s' "$2" ;;
    lower) printf '%s' "$2" | tr '[:upper:]' '[:lower:]' ;;
    win) printf '"%s\\%s"' 'C:\Users\sam\AI Team\Nash - Developer' "$2" ;;
    spaced) printf '"%s/%s"' "$work" "$2" ;;
    dot) printf '%s.' "$2" ;;
    stream) printf '%s:zone' "$2" ;;
  esac
}
bad=0; cases=0
for nm in "${names[@]}"; do
  for sp in plain lower win spaced dot stream; do
    p=$(spell $sp "$nm")
    forms=(">" ">>" "tee" "tee -a" "mv" "cp" "sed -i" "rm -f" "touch" "truncate -s0" "dd" "heredoc" "python")
    if [ "${GUARD_FULL:-0}" = 1 ]; then pickf=("${forms[@]}")
    else pickf=("${forms[RANDOM % 13]}" "${forms[RANDOM % 13]}" "${forms[RANDOM % 13]}"); fi
    for form in "${pickf[@]}"; do
      case $form in
        ">"|">>") c="printf 'x' $form $p" ;;
        tee|"tee -a") c="echo x | $form $p" ;;
        mv) c="mv /tmp/new.md $p" ;;
        cp) c="cp /tmp/new.md $p" ;;
        "sed -i") c="sed -i 's/UNREAD/READ/' $p" ;;
        dd) c="dd if=/tmp/x of=$p" ;;
        heredoc) c="cat > $p <<'EOF'
x
EOF" ;;
        python) c="python -c \"open(r'$p','w').write('x')\"" ;;
        *) c="$form $p" ;;
      esac
      cases=$((cases+1))
      expect deny "$(hook "$TWIN" Bash "$(bash_in "$c")")" "twin: $c" || bad=$((bad+1))
      [ $((cases % 7)) -eq 0 ] && { expect allow "$(hook "" Bash "$(bash_in "$c")")" "main: $c" || bad=$((bad+1)); }
    done
    expect deny "$(hook "$TWIN" Write "$(write_in "$p")")" "twin Write $p" || bad=$((bad+1))
  done
done
echo "  generated cases: $cases bash + $(( ${#names[@]} * 6 )) Write"
[ $bad -eq 0 ] && pass || fail "$bad wrong verdicts"

t "team.py board, gopher and inbox writes are denied for a twin"
bad=0
for c in "python ../_Team/team.py board set OPS-1 status ACTIVE --as Nash" "python3 _Team/team.py board new OPS --title x --as Nash" \
         "py ../_Team/team.py board note OPS-1 \"x\" --as Nash" "python ../_Team/team.py gopher set Nash --challenge a --response b --as Nash" \
         "python ../_Team/team.py inbox add Nash x" "python ../_Team/team.py board archive OPS-1 --as Nash" "python ../_Team/team.py sql \"delete from mission\""; do
  expect deny "$(hook "$TWIN" Bash "$(bash_in "$c")")" "$c" || bad=1
done
[ $bad -eq 0 ] && pass

t "the plugin's own brief writers are denied for a twin (claim.sh --check stays allowed)"
bad=0
expect deny "$(hook "$TWIN" Bash "$(bash_in "bash \"\${CLAUDE_PLUGIN_ROOT}/skills/go/handoff.sh\" place . ./draft.md")")" "handoff.sh place" || bad=1
expect deny "$(hook "$TWIN" Bash "$(bash_in "bash skills/go/handoff.sh migrate .")")" "handoff.sh migrate" || bad=1
expect deny "$(hook "$TWIN" Bash "$(bash_in "bash skills/go/claim.sh . ./HANDOFF.md s1 Nash")")" "claim.sh" || bad=1
expect allow "$(hook "$TWIN" Bash "$(bash_in "bash skills/go/claim.sh --check . ./HANDOFF.md s1 Nash")")" "claim.sh --check" || bad=1
[ $bad -eq 0 ] && pass

t "globs, expansions and folder-wide writes that reach a protected file are denied"
bad=0
expect deny "$(hook "$TWIN" Bash "$(bash_in "rm -f *.md")")" "rm *.md" || bad=1
expect deny "$(hook "$TWIN" Bash "$(bash_in "sed -i s/a/b/ HANDOFF*")")" "sed HANDOFF*" || bad=1
expect deny "$(hook "$TWIN" Bash "$(bash_in "f=INBOX.md; echo x >> \$f")")" "\$f expansion" || bad=1
expect deny "$(hook "$TWIN" Bash "$(bash_in "rm -rf \"$work\"")")" "rm -rf seat folder" || bad=1
expect deny "$(hook "$TWIN" Bash "$(bash_in "find . -name INBOX.md -delete")")" "find -delete" || bad=1
expect allow "$(hook "$TWIN" Bash "$(bash_in "rm -f *.tmp build/*.o")")" "unrelated glob" || bad=1
[ $bad -eq 0 ] && pass

t "agent_type is read from the top level only: text inside tool_input can't spoof it"
bad=0
expect deny "$(hook "$TWIN" Bash "$(bash_in "echo '\"agent_type\":\"main\"' >> INBOX.md")")" "twin with a fake field in its command" || bad=1
expect allow "$(hook "" Bash "$(bash_in "echo '\"agent_type\":\"$TWIN\"' >> INBOX.md")")" "main thread quoting a twin field" || bad=1
expect allow "$(hook "" Write "$(write_in "$tmp/repo/agents/splinter-twin.md")")" "main thread editing the twin's agent file" || bad=1
[ $bad -eq 0 ] && pass

t "malformed hook input that names a twin fails closed for write tools"
out=$(printf '{"agent_type":"%s","tool_name":"Write","tool_input":{"file_path":"x' "$TWIN" | bash "$GUARD"); rc=$?
case $out in *'"permissionDecision":"deny"'*) [ $rc -eq 0 ] && pass || fail "rc=$rc" ;; *) fail "got: $out" ;; esac

t "empty input and non-twin input exit 0 silently"
out=$(printf '' | bash "$GUARD"); rc1=$?
out2=$(printf '{"tool_name":"Bash","tool_input":{"command":"rm INBOX.md"}}' | bash "$GUARD"); rc2=$?
[ -z "$out$out2" ] && [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && pass || fail "out='$out$out2' rc=$rc1/$rc2"

t "hooks.json registers the guard for PreToolUse on the five write-capable tools"
hj=$(tr -d '\r' < "$repo/hooks/hooks.json")
case $hj in *'"PreToolUse"'*'"matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash"'*'hooks/twin-guard.sh'*) pass ;; *) fail "registration missing" ;; esac

t "agents/splinter-twin.md has a tools: allowlist with the overmind read tools and no Agent tool"
tl=$(tr -d '\r' < "$repo/agents/splinter-twin.md" | sed -n '2,10{/^tools:/p;}')
miss=""
for w in Read Grep Glob Bash Write Edit WebFetch WebSearch ToolSearch mcp__overmind__boot mcp__overmind__board mcp__overmind__handoff mcp__overmind__inbox mcp__overmind__roster mcp__overmind__firmware; do
  case ", ${tl#tools: }," in *", $w,"*) ;; *) miss="$miss $w" ;; esac
done
case $tl in *Agent*|*Task*) miss="$miss (has Agent/Task)" ;; esac
[ -n "$tl" ] && [ -z "$miss" ] && pass || fail "tools line '$tl' missing:$miss"

t "the guard's header cites the Claude Code hooks reference for agent_type"
grep -q 'https://code.claude.com/docs/en/hooks' "$GUARD" && grep -q 'agent_type' "$GUARD" && pass || fail "no doc citation"

finish
