#!/usr/bin/env bash
# hooks/twin-guard.sh -- PreToolUse guard: splinter twins never write the
# team's identity and state files (CONTRACT 4.9, 7.8; finding FW-25).
#
# Registered in hooks/hooks.json for PreToolUse with matcher
# "Write|Edit|MultiEdit|NotebookEdit|Bash".
#
# Platform facts this relies on, from the Claude Code hooks reference,
# https://code.claude.com/docs/en/hooks :
#   - "Common input fields": when a hook fires inside a subagent, the input
#     carries agent_id and agent_type, "Agent name (for example, "Explore" or
#     "security-reviewer")". A plugin agent reports its plugin-scoped name, so
#     this plugin's twin arrives as "ai-overmind:splinter-twin". The guard
#     matches any agent_type that contains "splinter-twin".
#   - "PreToolUse decision control": printing
#       {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#        "permissionDecision":"deny","permissionDecisionReason":"..."}}
#     and exiting 0 blocks the tool call.
#   - "Matcher patterns": a matcher of letters and "|" is a list of exact
#     tool names.
#
# Denied, for a twin only: Write, Edit, MultiEdit or NotebookEdit whose target
# (file_path or notebook_path) has a protected basename, and a Bash command
# that writes one through a redirect, tee, mv, cp, sed -i, rm, touch,
# truncate, ln, install, dd of=, find -delete/-exec, an interpreter
# (python, node, perl, ruby, pwsh) whose command names the file (its intent
# cannot be parsed, so it is refused; read with Read, cat or grep instead), the
# plugin's own brief writers (handoff.sh place|migrate, claim.sh without
# --check), a glob or $-expansion
# that can reach one, a recursive rm/mv of a folder holding one, or a
# team.py board|gopher|inbox|sql write. Protected (7.8, case-insensitive, either
# slash): INBOX.md, HANDOFF.md, HANDOFF-*.md, mission-complete*.md,
# GOPHER_REGISTRY.md, MISSION_BOARD.md, team.db, any path containing /_claims/.
# NTFS aliases of a name (trailing dots or spaces, an :alternate-stream
# suffix) count as the name.
#
# Allowed always: every read, every tool call outside a twin, and a twin's
# writes to any other path (its deliverables).
#
# Known limits (defense in depth; the twin's tools: allowlist and its
# instructions are the first line): 8.3 short names, and paths assembled at
# run time by programs this parser cannot see into.
#
# Input is capped at 512 KiB. A session that is not a twin pays one builtin
# read and one substring test. Every path exits 0.

IFS= read -r -d '' -n 524288 in
case $in in *splinter-twin*) ;; *) exit 0 ;; esac

deny() {
  local why=${1//[^A-Za-z0-9 ._:\/()-]/}
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Splinter twins never write team state files (%s). Report the change to your spawner instead."}}\n' "${why:0:200}"
  exit 0
}

# Minimal JSON reader: top-level agent_type and tool_name, and tool_input's
# file_path, notebook_path and command. A key name inside a string value is
# never mistaken for a key. Escapes are decoded; \uXXXX below 128 too.
parsed=$(printf '%s' "$in" | LC_ALL=C awk 'BEGIN { RS = "\001" }
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
    if (path == "/agent_type" || path == "/tool_name" || path == "/tool_input/file_path" || path == "/tool_input/notebook_path" || path == "/tool_input/command") {
      if (!(path in seen)) { seen[path] = 1; gsub(/\n/, "\002", v); print substr(path, 2) "\t" v }
    }
  }
  { s = $0; n = length(s); p = 1; bad = 0; val("", 0); ws(); if (bad || p <= n) print "ERR\t1" }')

agent="" tool="" fpath="" cmd="" err=""
nl=$'\n' ctl=$'\002'
while IFS= read -r line; do
  k=${line%%$'\t'*}; v=${line#*$'\t'}
  case $k in
    agent_type) agent=$v ;;
    tool_name) tool=$v ;;
    tool_input/file_path|tool_input/notebook_path) [ -n "$fpath" ] || fpath=$v ;;
    tool_input/command) cmd=${v//$ctl/$nl} ;;
    ERR) err=1 ;;
  esac
done <<EOF
$parsed
EOF

if [ -n "$err" ]; then
  # Malformed input that names a twin: fail closed for the write tools.
  case $in in *'"Write"'*|*'"Edit"'*|*'"MultiEdit"'*|*'"NotebookEdit"'*|*'"Bash"'*) deny "unreadable hook input" ;; esac
  exit 0
fi
case $agent in *splinter-twin*) ;; *) exit 0 ;; esac

# Names compare case-insensitively (NTFS and APFS ignore case) with builtins
# only: no fork per comparison.
shopt -s nocasematch

# prot PATH -> 0 when PATH names a protected file.
prot() {
  local p b
  p=${1//\\//}
  p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
  case "/$p/" in */_claims/*) return 0 ;; esac
  b=${p%/}; b=${b##*/}
  # NTFS aliases: an :alternate-stream suffix, then trailing dots and spaces.
  case $b in ?*:*) b=${b%%:*} ;; esac
  while :; do case $b in *.|*' ') b=${b%?} ;; *) break ;; esac; done
  case $b in
    inbox.md|handoff.md|handoff-*.md|mission-complete*.md|gopher_registry.md|mission_board.md|team.db) return 0 ;;
  esac
  return 1
}

# globhit PATTERN -> 0 when a glob basename could match a protected name.
globhit() {
  local g b
  g=${1//\\//}; b=${g##*/}
  case "/$g/" in */_claims/*) return 0 ;; esac
  for name in inbox.md handoff.md handoff-x.md mission-complete.md mission-complete-x.md gopher_registry.md mission_board.md team.db; do
    # shellcheck disable=SC2053
    [[ $name == $b ]] && return 0
  done
  return 1
}

# dirhit PATH -> 0 when PATH is a folder (relative to the hook's cwd) that holds
# a protected file within three levels.
dirhit() {
  local d=$1 c
  c=${in#*\"cwd\"}; c=${c#*\"}; c=${c%%\"*}; c=${c//\\\\//}
  case $d in /*|[A-Za-z]:*) ;; *) [ -n "$c" ] && d="$c/$d" ;; esac
  [ -d "$d" ] || return 1
  [ -n "$(find "$d" -maxdepth 3 \( -iname INBOX.md -o -iname HANDOFF.md -o -iname 'HANDOFF-*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _claims \) -print 2>/dev/null | head -n 1)" ]
}

case $tool in
  Write|Edit|MultiEdit|NotebookEdit)
    [ -n "$fpath" ] && prot "$fpath" && deny "$tool on ${fpath##*[/\\]}"
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac
[ -n "$cmd" ] || exit 0

lc=$cmd
mentions=0
for name in inbox.md handoff.md handoff- mission-complete gopher_registry.md mission_board.md team.db _claims; do
  case $lc in *"$name"*) mentions=1 ;; esac
done

# team.py writes to the board, registry or inbox.
re_team='team\.py.*[[:space:]](board[[:space:]]+(new|set|note|archive)|gopher[[:space:]]+set|inbox|sql)([[:space:]]|$)'
[[ $lc =~ $re_team ]] && deny "team.py write"
# The plugin's own brief writers: handoff.sh place|migrate and claim.sh (which
# stamps a brief); claim.sh --check only reads.
re_brief='handoff\.sh["'"'"']?[[:space:]]+(place|migrate)'
[[ $lc =~ $re_brief ]] && deny "handoff.sh write"
re_claim='claim\.sh["'"'"']?[[:space:]]+([^-]|-[^-]|--[^c])'
[[ $lc =~ $re_claim ]] && deny "claim.sh stamp"

# Check one write target: a protected name, a glob that reaches one, a
# $-expansion when the command names one, or a folder that holds one.
target() {
  local t=$1 rec=${2:-0}
  t=${t#\"}; t=${t%\"}; t=${t#\'}; t=${t%\'}
  [ -n "$t" ] || return 0
  case $t in /dev/null|/dev/stdout|/dev/stderr|'&'*) return 0 ;; esac
  prot "$t" && deny "write to ${t##*[/\\]}"
  case $t in *'$'*|*'`'*) [ $mentions -eq 1 ] && deny "expanded write target in a command naming a protected file" ;; esac
  case $t in *'*'*|*'?'*|*'['*) globhit "$t" && deny "glob write target $t" ;; esac
  [ "$rec" = 1 ] && dirhit "$t" && deny "folder write on $t"
  return 0
}

# Redirections, anywhere in the command (heredocs and subshells included).
rest=$cmd
re_redir='(^|[^0-9&<>])[0-9]*(>>|>[|]|[&]>>|[&]>|>)[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|<>()]+)'
while [[ $rest =~ $re_redir ]]; do
  target "${BASH_REMATCH[3]}"
  rest=${rest#*"${BASH_REMATCH[0]}"}
done

# split_words STRING -> words[]: whitespace-separated, honoring '...' and
# "..." quoting (a quoted path with spaces stays one word). Backslashes are
# kept as path characters.
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

# Simple commands: split on ; | & && || newlines and parentheses.
set -f
segs=$(printf '%s\n' "$cmd" | tr ';&|()' '\n\n\n\n\n')
while IFS= read -r seg; do
  split_words "$seg"
  [ ${#words[@]} -gt 0 ] || continue
  i=0
  while [ $i -lt ${#words[@]} ]; do
    case ${words[i]} in *=*|sudo|command|env|exec|nohup|time|xargs|builtin) i=$((i+1)) ;; *) break ;; esac
  done
  [ $i -lt ${#words[@]} ] || continue
  verb=${words[i]##*/}; verb=${verb%.[Ee][Xx][Ee]}
  args=("${words[@]:i+1}")
  [ ${#args[@]} -gt 0 ] || continue
  rec=0
  for a in "${args[@]}"; do case $a in -*[rR]*|--recursive) rec=1 ;; esac; done
  case $verb in
    tee|rm|rmdir|mv|touch|truncate|unlink|shred|chmod|chown)
      [ "$verb" = mv ] && rec=1
      for a in "${args[@]}"; do case $a in -*) ;; *) target "$a" "$rec" ;; esac; done ;;
    cp|ln|install|rsync|scp)
      last=""; for a in "${args[@]}"; do case $a in -*) ;; *) last=$a ;; esac; done
      target "$last" ;;
    dd)
      for a in "${args[@]}"; do case $a in of=*) target "${a#of=}" ;; esac; done
      [ $mentions -eq 1 ] && deny "dd naming a protected file" ;;
    sed|gsed|perl)
      inplace=0
      for a in "${args[@]}"; do case $a in -i*|--in-place*|-[a-hj-zA-Z]*i*) inplace=1 ;; esac; done
      if [ $inplace -eq 1 ]; then for a in "${args[@]}"; do case $a in -*) ;; *) target "$a" ;; esac; done; fi
      [ "$verb" = perl ] && [ $mentions -eq 1 ] && deny "interpreter naming a protected file" ;;
    find)
      case " ${args[*]} " in *' -delete '*|*' -exec'*|*' -ok'*) [ $mentions -eq 1 ] && deny "find writing a protected file" ;; esac ;;
    python|python3|py|node|ruby|pwsh|powershell|php|osascript)
      [ $mentions -eq 1 ] && deny "$verb naming a protected file" ;;
  esac
done <<EOF
$segs
EOF
set +f
exit 0
