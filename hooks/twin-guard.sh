#!/usr/bin/env bash
# hooks/twin-guard.sh -- splinter twins never write the team's identity and
# state files (CONTRACT 4.9, 7.8; AMENDMENTS A-25; finding FW-25).
#
# This is a SEATBELT against a misled twin, not a sandbox (reference/twins.md).
# It has two parts:
#   1. Pre-check (PreToolUse, matcher "Write|Edit|MultiEdit|NotebookEdit|Bash"):
#      deny a twin's tool call that targets or names a protected file.
#   2. Outcome detector (A-25.3): before every twin Bash call that the
#      pre-check allows, snapshot cksum and size of every protected file under
#      the team root; after the call (PostToolUse or PostToolUseFailure, matcher
#      "Bash"), compare. Any change prints a "TWIN-GUARD ALERT: protected file
#      changed during twin command: <relpath>" line as additionalContext and
#      appends it to <team-root>/_twin-guard.log. It never restores: another
#      session may have written the same file legitimately in that window.
#      _claims/ is excluded, because TARS rewrites it every turn.
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
# at run time (the detector catches it after the fact, it does not prevent
# it); a Bash command left running in the background past the PostToolUse
# check; 8.3 short names; a write through a symlink by the Write tool; another
# session writing in the same window (the detector alerts, it can't tell who).
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
# team root, CONTRACT 7.1: the cwd or its parent, whichever holds
# MISSION_BOARD.md; failing that, the same test on the session's project dir.
teamroot() {
  local d
  for d in "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    d=${d//\\//}; d=${d%/}
    [ -n "$d" ] && [ -d "$d" ] || continue
    if [ -f "$d/MISSION_BOARD.md" ]; then (cd "$d" && pwd); return; fi
    if [ -f "$d/../MISSION_BOARD.md" ]; then (cd "$d/.." && pwd); return; fi
  done
}

# snapshot ROOT -> "<cksum> <size> <relpath>" per protected file, sorted.
snapshot() {
  local r=$1
  {
    find "$r" -maxdepth 4 \( -name .git -o -name node_modules -o -name _claims \) -prune -o -type f \
      \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md \
         -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md \
         -o -iname MISSION_BOARD.md -o -iname team.db -o -path '*/.go-claim/*' -o -path '*/_ids/*' \) \
      -exec cksum {} + 2>/dev/null
    find "$r" -maxdepth 4 \( -name .git -o -name node_modules -o -name _claims \) -prune -o -type d \
      \( -path '*/.go-claim/*' -o -path '*/_ids/*' \) -print 2>/dev/null | sed 's/^/dir 0 /'
  } | awk -v r="$r/" '{ p = $0; sub(/^[^ ]+ [^ ]+ /, "", p); if (index(p, r) == 1) p = substr(p, length(r) + 1); print $1 " " $2 " " p }' | sort
}

sanit() { local s=${1//[^A-Za-z0-9_-]/}; printf '%s' "${s:0:64}"; }
snapfile="${TMPDIR:-${TMP:-/tmp}}/ovm-twin-$(sanit "${aid:-noagent}")-$(sanit "${tuid:-notool}").snap"

# ---------------------------------------------------------------- post: detect
if [ "$event" != PreToolUse ]; then
  [ "$tool" = Bash ] && [ -f "$snapfile" ] || exit 0
  root=""; IFS= read -r root < "$snapfile"; root=${root#root }
  [ -n "$root" ] && [ -d "$root" ] || { rm -f "$snapfile"; exit 0; }
  changed=$(snapshot "$root" | awk 'NR == FNR { if (FNR > 1) { k = $0; sub(/^[^ ]+ [^ ]+ /, "", k); old[k] = $1 " " $2 } ; next }
    { k = $0; sub(/^[^ ]+ [^ ]+ /, "", k); now[k] = 1; if (!(k in old) || old[k] != $1 " " $2) print k }
    END { for (k in old) if (!(k in now)) print k }' "$snapfile" - | sort -u)
  rm -f "$snapfile"
  [ -n "$changed" ] || exit 0
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  ctx="" ; sep=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    msg="TWIN-GUARD ALERT: protected file changed during twin command: $rel"
    printf '%s agent=%s id=%s %s\n' "$ts" "$(sanit "$agent")" "$(sanit "$aid")" "$msg" >> "$root/_twin-guard.log" 2>/dev/null
    ctx="$ctx$sep$msg"; sep=$'\n'
  done <<EOF
$changed
EOF
  ctx="$ctx"$'\n'"This twin's result is quarantined until the human or the orchestrator reviews the diff (reference/twins.md). Report this alert to your spawner."
  esc=${ctx//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}; esc=${esc//$'\r'/}; esc=${esc//$'\t'/ }
  esc=$(printf '%s' "$esc" | tr -d '\000-\010\013\014\016-\037')
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$esc"
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
# Allowed. Record the protected files so the PostToolUse check can compare.
root=$(teamroot)
if [ -n "$root" ]; then
  { printf 'root %s\n' "$root"; snapshot "$root"; } > "$snapfile" 2>/dev/null || rm -f "$snapfile"
fi
exit 0
