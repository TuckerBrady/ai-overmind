#!/usr/bin/env bash
# hooks/twin-guard.sh -- splinter twins never write the team's identity and
# state files (CONTRACT 4.9, 7.8; AMENDMENTS A-25; finding FW-25).
#
# This is a SEATBELT against a misled twin, not a sandbox (reference/twins.md).
# It has two parts:
#   1. Pre-check (PreToolUse, matcher "Write|Edit|MultiEdit|NotebookEdit|Bash"):
#      deny a twin's tool call that targets or names a protected file.
#   2. Outcome detector (A-25.3, round 4): before every twin Bash call that the
#      pre-check allows, record a sha256 of every protected file under the team
#      root, with a marker, in a per-call file keyed by agent_id and tool_use_id
#      inside a folder the guard creates with mode 700. After the call
#      (PostToolUse or PostToolUseFailure, matcher "Bash"), compare. Any change
#      prints a "TWIN-GUARD ALERT: protected file changed during twin command:
#      <relpath>" line as additionalContext and appends it to
#      <team-root>/_twin-guard.log; a missing record prints "TWIN-GUARD ALERT:
#      snapshot missing". It never restores: another session may have written
#      the same file legitimately in that window. _claims/ is excluded, because
#      TARS rewrites it every turn. Write and Edit are not snapshotted; they are
#      denied by path before they run. Team root: the outermost folder holding
#      MISSION_BOARD.md among the cwd and up to three folders above it (else the
#      project dir); with none in reach, only the pre-check runs. The walk prunes
#      drafts/, .git/, node_modules/ and any repo clone (a folder holding .git),
#      and a Pre snapshot over 5 s is logged as "detector over budget" (the hook
#      has 10 s; output after a timeout is discarded).
#
# Platform facts, from the Claude Code hooks reference,
# https://code.claude.com/docs/en/hooks :
#   - "Common input fields": inside a subagent the input carries agent_id and
#     agent_type ("Agent name (for example, "Explore" or "security-reviewer")").
#     A plugin agent reports its plugin-scoped name, so this plugin's twin
#     arrives as "ai-overmind:splinter-twin"; any agent_type containing
#     "splinter-twin" counts. PostToolUse input carries the same fields plus
#     tool_use_id, so the snapshot is keyed by agent_id and tool_use_id.
#   - "PreToolUse decision control": {"hookSpecificOutput":{"hookEventName":
#     "PreToolUse","permissionDecision":"deny","permissionDecisionReason":...}}
#     on stdout, exit 0, blocks the call.
#   - "PostToolUse decision control" and "Add context for Claude":
#     {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":
#     "..."}} adds the text next to the tool result. PostToolUseFailure (a
#     failed call, such as a non-zero Bash exit) takes the same form.
#   - "Matcher patterns": letters and "|" make a list of exact tool names.
#
# Protected (7.8 as amended by A-25.1; case-insensitive; either slash; NTFS
# aliases, trailing dots or spaces and :streams, count as the name):
#   INBOX.md  HANDOFF*.md  BOOT.md  CLAUDE.md  WORKING_WITH_*.md
#   mission-complete*.md  GOPHER_REGISTRY.md  MISSION_BOARD.md  team.db
#   _twin-guard.log, and any path through _claims/, .go-claim/ or _ids/.
#   Any basename with ~<digit> (an 8.3 short name such as MISSIO~1.MD) is
#   treated as protected, since NTFS can alias it to any of these.
#
# Pre-check rules for Bash (A-25.2). The command is matched with ', " and \
# removed, so IN''BOX.md and INB\OX.md are INBOX.md.
#   - eval, source and . are denied outright.
#   - A redirect target containing $ or ` is denied; so is one that names, or
#     as a glob can match, a protected file.
#   - cp, mv, ln, install, rsync and scp: every non-option argument is checked,
#     sources included (a hard link is a second name for the file). Their
#     destination may not be a protected folder or a seat folder holding
#     protected files; for mv, no argument may be.
#   - tee, rm, touch, truncate, chmod and friends, dd of=, sed -i, perl -i,
#     find -delete/-exec, team.py board|gopher|inbox|sql writes, and the
#     plugin's own brief writers (handoff.sh place|migrate, claim.sh) are
#     checked the same way.
#   - An argument built from $-expansion is denied when what's left of its last
#     path part could complete a protected name (${f}OX.md, $f, $x.md).
#   - Interpreters, matched by prefix (python*, node, perl*, ruby*, bun, deno,
#     uv, cmd, powershell, pwsh, sqlite3, ed, vim, patch, tar, xargs, and sh or
#     bash with -c), are denied when the command names a protected file or
#     _Team.
#   - Catch-all: when the command names a protected file anywhere, every part
#     of it that does so must start with a read-only verb (cat, grep, head,
#     tail, wc, diff, less, awk without -i, sed without -i, git
#     log|show|diff|status) and no redirection may write a file.
# Input over the 512 KiB cap that names a twin fails CLOSED at PreToolUse.
#
# Residual risks (reference/twins.md): a program that builds a protected path
# at run time (reported after the fact, not prevented); a Bash command left
# running in the background past the PostToolUse check; files outside the
# root, under the pruned folders, or anywhere when no root is in reach or the
# snapshot outruns the timeout; a same-user program that finds and rewrites
# the call's record; a Write through a symlink; another session writing in the
# same window (the detector alerts, it can't tell who).
#
# A session that is not a twin pays one builtin read and one substring test.
# Every path exits 0.

export LC_ALL=C
CAP=524288
IFS= read -r -d '' -n $((CAP + 1)) in
case $in in *splinter-twin*) ;; *) exit 0 ;; esac

event=PreToolUse
case $in in *'"hook_event_name":"PostToolUseFailure"'*|*'"hook_event_name": "PostToolUseFailure"'*) event=PostToolUseFailure ;;
  *'"hook_event_name":"PostToolUse"'*|*'"hook_event_name": "PostToolUse"'*) event=PostToolUse ;; esac

deny() {
  local why=${1//[^A-Za-z0-9 ._:\/()-]/}
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Splinter twins never write team state files (%s). Report the change to your spawner instead."}}\n' "${why:0:200}"
  exit 0
}

if [ ${#in} -gt $CAP ]; then
  [ "$event" = PreToolUse ] && deny "hook input over the 512 KiB cap"
  exit 0
fi

# Minimal JSON reader: top-level fields and tool_input's file_path,
# notebook_path and command. A key name inside a string value is never
# mistaken for a key. Escapes are decoded; \uXXXX below 128 too.
parsed=$(printf '%s' "$in" | awk 'BEGIN { RS = "\001" }
  function ws() { while (p <= n && index(" \t\r\n", substr(s, p, 1))) p++ }
  function hex(h,   i, v, c) { v = 0; for (i = 1; i <= 4; i++) { c = index("0123456789abcdef", tolower(substr(h, i, 1))); if (!c) return -1; v = v * 16 + c - 1 } return v }
  function str(   o, c, e, v) {
    if (substr(s, p, 1) != "\"") { bad = 1; return "" }
    p++; o = ""
    while (p <= n) {
      c = substr(s, p, 1)
      if (c == "\"") { p++; return o }
      if (c == "\\") {
        e = substr(s, p + 1, 1); p += 2
        if (e == "n") o = o "\n"; else if (e == "t") o = o " "; else if (e == "r") o = o "\n"
        else if (e == "b" || e == "f") o = o " "
        else if (e == "u") { v = hex(substr(s, p, 4)); p += 4; o = o ((v >= 32 && v < 127) ? sprintf("%c", v) : (v == 10 || v == 13 ? "\n" : "?")) }
        else o = o e
        continue
      }
      o = o c; p++
    }
    bad = 1; return o
  }
  function val(path, depth,   c, k, i, v) {
    if (depth > 64) { bad = 1; return }
    ws(); c = substr(s, p, 1)
    if (c == "{") {
      p++; ws()
      if (substr(s, p, 1) == "}") { p++; return }
      while (!bad && p <= n) {
        ws(); k = str(); ws()
        if (substr(s, p, 1) != ":") { bad = 1; return }
        p++; val(path "/" k, depth + 1); ws(); c = substr(s, p, 1)
        if (c == ",") { p++; continue }
        if (c == "}") { p++; return }
        bad = 1; return
      }
      bad = 1; return
    }
    if (c == "[") {
      p++; ws()
      if (substr(s, p, 1) == "]") { p++; return }
      i = 0
      while (!bad && p <= n) {
        val(path "/" i++, depth + 1); ws(); c = substr(s, p, 1)
        if (c == ",") { p++; continue }
        if (c == "]") { p++; return }
        bad = 1; return
      }
      bad = 1; return
    }
    if (c == "\"") { v = str() }
    else { v = ""; while (p <= n && !index(",}] \t\r\n", substr(s, p, 1))) { v = v substr(s, p, 1); p++ } if (v == "") { bad = 1; return } }
    if (path ~ /^\/(agent_type|agent_id|tool_name|tool_use_id|cwd|hook_event_name)$/ || path == "/tool_input/file_path" || path == "/tool_input/notebook_path" || path == "/tool_input/command") {
      if (!(path in seen)) { seen[path] = 1; gsub(/\n/, "\002", v); print substr(path, 2) "\t" v }
    }
  }
  { s = $0; n = length(s); p = 1; bad = 0; val("", 0); ws(); if (bad || p <= n) print "ERR\t1" }')

agent="" aid="" tool="" tuid="" cwd="" fpath="" cmd="" err=""
nl=$'\n' ctl=$'\002' tab=$'\t'
while IFS= read -r line; do
  k=${line%%"$tab"*}; v=${line#*"$tab"}
  case $k in
    agent_type) agent=$v ;;
    agent_id) aid=$v ;;
    tool_name) tool=$v ;;
    tool_use_id) tuid=$v ;;
    hook_event_name) case $v in PreToolUse|PostToolUse|PostToolUseFailure) event=$v ;; esac ;;
    cwd) cwd=${v//\\//} ;;
    tool_input/file_path|tool_input/notebook_path) [ -n "$fpath" ] || fpath=$v ;;
    tool_input/command) cmd=${v//$ctl/$nl} ;;
    ERR) err=1 ;;
  esac
done <<EOF
$parsed
EOF

if [ -n "$err" ]; then
  # Malformed input that names a twin: fail closed for the write tools.
  [ "$event" = PreToolUse ] && deny "unreadable hook input"
  exit 0
fi
case $agent in *splinter-twin*) ;; *) exit 0 ;; esac

# ---------------------------------------------------------------- shared
# Team root, CONTRACT 7.1 extended (round 4): the OUTERMOST of the cwd and up
# to three folders above it that holds MISSION_BOARD.md (live seat folders keep
# stale MISSION_BOARD.md copies, and the nearest would shrink the snapshot to one
# seat); failing that, the same walk from the session's project dir. With no team root the pre-check still
# runs; only the detector is off (reference/twins.md).
teamroot() {
  local d n found
  for d in "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    d=${d//\\//}; d=${d%/}
    [ -n "$d" ] && [ -d "$d" ] || continue
    n=0 found=""
    while [ $n -le 3 ]; do
      [ -f "$d/MISSION_BOARD.md" ] && found=$d
      d="$d/.."; n=$((n + 1))
    done
    if [ -n "$found" ]; then (cd "$found" && pwd); return; fi
  done
}

# The hash for the snapshot: sha256 (sha256sum, else shasum -a 256), cksum
# (CRC32 plus size) only as the last fallback.
if command -v sha256sum >/dev/null 2>&1; then HASH="sha256sum"
elif command -v shasum >/dev/null 2>&1; then HASH="shasum -a 256"
else HASH="cksum"; fi

# snapshot ROOT -> "<hash> <relpath>" per protected file ("dir <relpath>" for a
# claim or ID folder), sorted. Protected names match at any depth. Pruned:
# .git, node_modules, drafts, _claims (TARS's), and any folder that holds a
# .git (a repo clone): none of them hold team state, and walking them can
# blow the hook's 10 s timeout.
snapshot() {
  local r=$1 g pr=()
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    g=${g%/.git}; [ "$g" = "$r" ] && continue
    pr+=(-o -path "$g")
  done <<EOF
$(find "$r" \( -name node_modules -o -name drafts -o -name _claims \) -prune -o -name .git -print -prune 2>/dev/null)
EOF
  find "$r" \( -name .git -o -name node_modules -o -name drafts -o -name _claims ${pr[@]+"${pr[@]}"} \) -prune -o \
    \( -type f \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md \
         -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md \
         -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _twin-guard.log \
         -o -path '*/.go-claim/*' -o -path '*/_ids/*' \) -exec $HASH {} + \) -o \
    \( -type d \( -path '*/.go-claim/*' -o -path '*/_ids/*' \) -print \) 2>/dev/null |
  awk -v r="$r/" -v ck="$([ "$HASH" = cksum ] && echo 1 || echo 0)" '
    {
      if (index($0, r) == 1) { print "dir " substr($0, length(r) + 1); next }
      if (ck) { h = $1 ":" $2; p = $0; sub(/^[^ ]+ [^ ]+ /, "", p) }
      else { h = $1; p = $0; sub(/^[^ ]+ [ *]?/, "", p) }
      if (index(p, r) == 1) p = substr(p, length(r) + 1)
      print h " " p
    }' | LC_ALL=C sort
}

sanit() { local s=${1//[^A-Za-z0-9_-]/}; printf '%s' "${s:0:64}"; }
# Per-call records live in a folder the guard creates with mode 700; each call
# gets its own snapshot and marker, keyed by agent_id and tool_use_id.
gdir="${TMPDIR:-${TMP:-/tmp}}/ovm-twin-guard"
callid="$(sanit "${aid:-noagent}").$(sanit "${tuid:-notool}")"
snapfile="$gdir/$callid.snap"; markfile="$gdir/$callid.ok"
BUDGET=5

alert() { # ROOT EVENT LINES... -> log each line under ROOT, print them as context
  local root=$1 ev=$2 ts ctx="" sep="" msg esc
  shift 2
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  for msg in "$@"; do
    [ -n "$root" ] && printf '%s agent=%s id=%s tool_use=%s %s\n' "$ts" "$(sanit "$agent")" "$(sanit "$aid")" "$(sanit "$tuid")" "$msg" >> "$root/_twin-guard.log" 2>/dev/null
    ctx="$ctx$sep$msg"; sep=$'\n'
  done
  ctx="$ctx"$'\n'"This twin's result is quarantined until the human or the orchestrator reviews the diff (reference/twins.md). Report this alert to your spawner."
  esc=${ctx//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}; esc=${esc//$'\r'/}; esc=${esc//$'\t'/ }
  esc=$(printf '%s' "$esc" | tr -d '\000-\010\013\014\016-\037')
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$ev" "$esc"
}

# ---------------------------------------------------------------- post: detect
if [ "$event" != PreToolUse ]; then
  [ "$tool" = Bash ] || exit 0
  root=$(teamroot)
  if [ ! -f "$markfile" ] || [ ! -f "$snapfile" ]; then
    # Pre allowed this call (Post only fires for a call that ran), so its record
    # must exist. A missing record means something removed it.
    rm -f "$snapfile" "$markfile" 2>/dev/null
    alert "$root" "$event" "TWIN-GUARD ALERT: snapshot missing for this twin command; protected files were not checked"
    exit 0
  fi
  mark=""; IFS= read -r mark < "$markfile"
  sroot=""; IFS= read -r sroot < "$snapfile"; sroot=${sroot#root }
  rm -f "$markfile"
  case $mark in
    noroot) rm -f "$snapfile"; exit 0 ;;
  esac
  if [ "$mark" != "ok $callid" ] || [ -z "$sroot" ] || [ ! -d "$sroot" ]; then
    rm -f "$snapfile"
    alert "$root" "$event" "TWIN-GUARD ALERT: snapshot missing for this twin command; protected files were not checked"
    exit 0
  fi
  changed=$(snapshot "$sroot" | awk 'NR == FNR { if (FNR > 1) { k = $0; sub(/^[^ ]+ /, "", k); old[k] = $1 } ; next }
    { k = $0; sub(/^[^ ]+ /, "", k); now[k] = 1; if (!(k in old) || old[k] != $1) print k }
    END { for (k in old) if (!(k in now)) print k }' "$snapfile" - | LC_ALL=C sort -u)
  rm -f "$snapfile"
  [ -n "$changed" ] || exit 0
  msgs=()
  while IFS= read -r rel; do
    [ -n "$rel" ] && msgs+=("TWIN-GUARD ALERT: protected file changed during twin command: $rel")
  done <<EOF
$changed
EOF
  alert "$sroot" "$event" "${msgs[@]}"
  exit 0
fi

# ---------------------------------------------------------------- pre: deny
# Names compare case-insensitively (NTFS and APFS ignore case), builtins only.
shopt -s nocasematch

# pname BASENAME -> 0 when it is a protected name (NTFS aliases folded).
pname() {
  local b=$1
  case $b in ?*:*) b=${b%%:*} ;; esac
  while :; do case $b in *.|*' ') b=${b%?} ;; *) break ;; esac; done
  # An 8.3 short name (MISSIO~1.MD) can alias any protected file on NTFS.
  case $b in *~[0-9]*) return 0 ;; esac
  case $b in
    inbox.md|handoff*.md|boot.md|claude.md|working_with_*.md|mission-complete*.md|gopher_registry.md|mission_board.md|team.db|_twin-guard.log|_claims|.go-claim|_ids) return 0 ;;
  esac
  return 1
}
# prot PATH -> 0 when PATH names a protected file or runs through a protected
# folder. Backslashes are tried both as separators and as escapes.
prot() {
  local p q
  for q in "${1//\\//}" "${1//\\/}"; do
    p=$q; p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
    case "/$p/" in */_claims/*|*/.go-claim/*|*/_ids/*) return 0 ;; esac
    p=${p%/}; pname "${p##*/}" && return 0
  done
  return 1
}
protnames="inbox.md handoff.md handoff-x.md boot.md claude.md working_with_x.md mission-complete.md mission-complete-x.md gopher_registry.md mission_board.md team.db _twin-guard.log _claims .go-claim _ids"
# globhit PATTERN -> 0 when a glob's last part could match a protected name.
globhit() {
  local g=${1//\\//} b name
  b=${g##*/}
  case "/$g/" in */_claims/*|*/.go-claim/*|*/_ids/*) return 0 ;; esac
  for name in $protnames; do
    # shellcheck disable=SC2053
    [[ $name == $b ]] && return 0
  done
  return 1
}
# dolhit ARG -> 0 when ARG has a $- or `-expansion in its last part and what
# is left of that part could complete a protected name.
dolhit() {
  local t=${1//\\//} lit name
  t=${t##*/}
  case $t in *'$'*|*'`'*) ;; *) return 1 ;; esac
  lit=$(printf '%s' "$t" | sed -e 's/\${[^}]*}//g' -e 's/\$[A-Za-z0-9_@*#?!-]*//g' -e 's/`[^`]*`//g')
  [ -z "$lit" ] && return 0
  for name in $protnames; do
    case $name in *"$lit") return 0 ;; esac
  done
  return 1
}
# dirhit PATH -> 0 when PATH is a folder that is protected or holds a
# protected file within three levels.
dirhit() {
  local d=${1//\\//}
  case $d in /*|[A-Za-z]:*) ;; *) [ -n "$cwd" ] && d="$cwd/$d" ;; esac
  [ -d "$d" ] || return 1
  pname "${d%/}" && return 0
  [ -n "$(find "$d" -maxdepth 3 \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _claims -o -iname .go-claim -o -iname _ids \) -print 2>/dev/null | head -n 1)" ]
}

case $tool in
  Write|Edit|MultiEdit|NotebookEdit)
    [ -n "$fpath" ] && prot "$fpath" && deny "$tool on ${fpath##*[/\\]}"
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac
[ -n "$cmd" ] || exit 0

# The command with quotes and backslashes removed: split names rejoin.
norm=${cmd//\'/}; norm=${norm//\"/}; norm=${norm//\\/}
re_name='(inbox\.md|handoff[^[:space:];&|<>()/]*\.md|boot\.md|claude\.md|working_with_[^[:space:];&|<>()/]*\.md|mission-complete[^[:space:];&|<>()/]*\.md|gopher_registry\.md|mission_board\.md|team\.db|_twin-guard\.log|\.go-claim|(^|[^a-z0-9])_ids([/[:space:]]|$)|(^|[^a-z0-9])_claims([/[:space:]]|$))'
mentions=0; [[ $norm =~ $re_name ]] && mentions=1
re_teamdir='(^|[^a-z0-9])_team([/[:space:]]|$)'
mteam=0; [[ $norm =~ $re_teamdir ]] && mteam=1

re_team='team\.py.*[[:space:]](board[[:space:]]+(new|set|note|archive)|gopher[[:space:]]+set|inbox|sql)([[:space:]]|$)'
[[ $norm =~ $re_team ]] && deny "team.py write"
re_brief='handoff\.sh[[:space:]]+(place|migrate)'
[[ $norm =~ $re_brief ]] && deny "handoff.sh write"
re_claim='claim\.sh[[:space:]]+([^-]|-[^-]|--[^c])'
[[ $norm =~ $re_claim ]] && deny "claim.sh stamp"

# One write target.
target() {
  local t=$1 rec=${2:-0}
  t=${t#\"}; t=${t%\"}; t=${t#\'}; t=${t%\'}
  [ -n "$t" ] || return 0
  case $t in /dev/null|/dev/stdout|/dev/stderr|'&'*) return 0 ;; esac
  prot "$t" && deny "write to ${t##*[/\\]}"
  dolhit "$t" && deny "expanded write target"
  case $t in *'*'*|*'?'*|*'['*) globhit "$t" && deny "glob write target" ;; esac
  [ "$rec" = 1 ] && dirhit "$t" && deny "write to a folder holding team state"
  return 0
}

# Redirections, anywhere in the command (heredocs and subshells included).
writes_redirect=0
rest=$cmd
re_redir='(^|[^0-9&<>])[0-9]*(>>|>[|]|[&]>>|[&]>|>)[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|<>()]+)'
while [[ $rest =~ $re_redir ]]; do
  r=${BASH_REMATCH[3]}
  case $r in *'$'*|*'`'*) deny "redirect to an expanded target" ;; esac
  case $r in /dev/null|/dev/stdout|/dev/stderr|'&'*) ;; *) writes_redirect=1 ;; esac
  target "$r"
  rest=${rest#*"${BASH_REMATCH[0]}"}
done

# split_words STRING -> words[]: whitespace-separated, honoring '...' and
# "..." (a quoted path with spaces stays one word); backslashes kept.
split_words() {
  local s=$1 w="" q="" c i n have=0
  words=(); n=${#s}
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; else w="$w$c"; fi
    else
      case $c in
        "'"|'"') q=$c; have=1 ;;
        ' '|$'\t') [ $have -eq 1 ] && { words+=("$w"); w=""; have=0; } ;;
        *) w="$w$c"; have=1 ;;
      esac
    fi
  done
  [ $have -eq 1 ] && words+=("$w")
  return 0
}

readonly_ok() { # verb, args... -> 0 when the part only reads
  local v=$1; shift
  case $v in
    cat|grep|egrep|fgrep|head|tail|wc|diff|less) return 0 ;;
    awk|gawk) local a; for a in "$@"; do case $a in -i|-i*|--include*) return 1 ;; esac; done; return 0 ;;
    sed) local a; for a in "$@"; do case $a in -i*|--in-place*|-[a-z]*i*) return 1 ;; esac; done; return 0 ;;
    git) case ${1:-} in log|show|diff|status) return 0 ;; esac; return 1 ;;
  esac
  return 1
}

# Simple commands: split on ; & | ( ) and newlines.
set -f
segs=$(printf '%s\n' "$cmd" | tr ';&|()' '\n\n\n\n\n')
while IFS= read -r seg; do
  split_words "$seg"
  [ ${#words[@]} -gt 0 ] || continue
  i=0
  while [ $i -lt ${#words[@]} ]; do
    case ${words[i]} in *=*|sudo|command|env|exec|nohup|time|builtin|do|then|else|'{'|'!') i=$((i+1)) ;; *) break ;; esac
  done
  [ $i -lt ${#words[@]} ] || continue
  verb=${words[i]##*[/\\]}; verb=${verb%.[Ee][Xx][Ee]}
  args=("${words[@]:i+1}")
  sn=${seg//\'/}; sn=${sn//\"/}; sn=${sn//\\/}
  smention=0; [[ $sn =~ $re_name ]] && smention=1
  case $verb in eval|source|.) deny "$verb" ;; esac
  rec=0
  for a in ${args[@]+"${args[@]}"}; do case $a in -*[rR]*|--recursive) rec=1 ;; esac; done
  case $verb in
    cp|mv|ln|install|rsync|scp)
      last=""
      for a in ${args[@]+"${args[@]}"}; do
        case $a in -*) continue ;; esac
        last=$a
        if [ "$verb" = mv ]; then target "$a" 1; else target "$a"; fi
      done
      [ -n "$last" ] && target "$last" 1 ;;
    tee|rm|rmdir|touch|truncate|unlink|shred|chmod|chown|mkdir)
      for a in ${args[@]+"${args[@]}"}; do case $a in -*) ;; *) target "$a" "$rec" ;; esac; done ;;
    dd)
      for a in ${args[@]+"${args[@]}"}; do case $a in of=*) target "${a#of=}" ;; esac; done
      [ $mentions -eq 1 ] && deny "dd naming a protected file" ;;
    sed|gsed|perl*)
      inplace=0
      for a in ${args[@]+"${args[@]}"}; do case $a in -i*|--in-place*|-[a-hj-zA-Z]*i*) inplace=1 ;; esac; done
      if [ $inplace -eq 1 ]; then for a in ${args[@]+"${args[@]}"}; do case $a in -*) ;; *) target "$a" ;; esac; done; fi ;;
    find)
      case " ${args[*]} " in
        *' -delete '*|*' -exec'*|*' -ok'*)
          [ $mentions -eq 1 ] && deny "find writing a protected file"
          for a in ${args[@]+"${args[@]}"}; do globhit "$a" && deny "find pattern reaching a protected file"; done ;;
      esac ;;
  esac
  # Interpreters, by prefix.
  interp=0
  case $verb in
    python*|py|node|perl*|ruby*|bun|deno|uv|uvx|cmd|powershell|pwsh|sqlite3|ed|vim|vi|nvim|patch|tar|xargs|php|osascript) interp=1 ;;
    sh|bash|zsh|dash|ksh) case " ${args[*]} " in *' -c '*|*' -c'*) interp=1 ;; esac ;;
  esac
  if [ $interp -eq 1 ] && { [ $mentions -eq 1 ] || [ $mteam -eq 1 ]; }; then deny "$verb with a protected file in the command"; fi
  # Catch-all: a part that names a protected file must only read it.
  if [ $smention -eq 1 ]; then
    readonly_ok "$verb" ${args[@]+"${args[@]}"} || deny "$verb naming a protected file"
  fi
done <<EOF
$segs
EOF
set +f
[ $mentions -eq 1 ] && [ $writes_redirect -eq 1 ] && deny "a redirect in a command naming a protected file"

# ---------------------------------------------------------------- pre: snapshot
# Allowed. Record the protected files so the PostToolUse check can compare. The
# record is written for every allowed twin Bash call, "noroot" included, so a
# record missing at Post always means something removed it.
if [ -L "$gdir" ]; then rm -f "$gdir"; fi
( umask 077; mkdir -p "$gdir" ) 2>/dev/null; chmod 700 "$gdir" 2>/dev/null
root=$(teamroot)
if [ -z "$root" ]; then
  printf 'root \n' > "$snapfile"; printf 'noroot\n' > "$markfile"
  exit 0
fi
t0=$SECONDS
{ printf 'root %s\n' "$root"; snapshot "$root"; } > "$snapfile" 2>/dev/null
el=$((SECONDS - t0))
printf 'ok %s\n' "$callid" > "$markfile"
if [ "$el" -gt "$BUDGET" ]; then
  printf '%s agent=%s id=%s tool_use=%s TWIN-GUARD NOTE: detector over budget (%ss snapshot; budget %ss)\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$(sanit "$agent")" "$(sanit "$aid")" "$(sanit "$tuid")" "$el" "$BUDGET" >> "$root/_twin-guard.log" 2>/dev/null
fi
exit 0
