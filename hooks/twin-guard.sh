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
#      a live MISSION_BOARD.md (not a RETIRED BRIDGE COPY) among the cwd, the
#      session's project dir, and up to three folders above each (A-37 B2);
#      with none in reach, only the pre-check runs, and a Post
#      that finds a root the Pre did not alerts (A-33 S-2). The walk prunes
#      drafts/, .git/, node_modules/ and any repo clone (a folder holding .git),
#      except a folder that also holds a BOOT.md (a seat kept in git): there
#      only the .git is pruned (A-33 S-1). A Pre snapshot over 5 s is logged as
#      "detector over budget" (the hook has 10 s; output after a timeout is
#      discarded).
#      Every protected file is hashed on every Pre and every Post (A-37 B1):
#      file times and sizes are never trusted to show a file is unchanged.
#      Every live root the two walks find is snapshotted (A-38 P2). Post
#      re-hashes the files Pre recorded and logs any change before it walks
#      for new ones; a per-call busy marker lets the next Pre report a check
#      that never finished (A-38 P1).
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
#   _twin-guard.log, and any path through _claims/, .go-claim/, _ids/ or the
#   guard's own record folder ovm-twin-guard/ (A-33 S-2).
#   Any basename with ~<digit> (an 8.3 short name such as MISSIO~1.MD) is
#   treated as protected, since NTFS can alias it to any of these.
#
# Pre-check rules for Bash (A-25.2). The command is matched with ', " and \
# removed, so IN''BOX.md and INB\OX.md are INBOX.md.
#   - eval and source are denied outright, and so is . when it starts a
#     simple command outside quotes (a quoted " . " is perl's concatenation).
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
# Input over the 512 KiB cap is streamed whole to find agent_type before the
# twin test (A-33 S-3): a twin fails CLOSED, a main session is never refused.
#
# Residual risks (reference/twins.md): a program that builds a protected path
# at run time (reported after the fact, not prevented); a Bash command left
# running in the background past the PostToolUse check; files outside the
# root, under the pruned folders, or anywhere when no root is in reach or the
# snapshot outruns the timeout; a same-user program that finds and rewrites
# the call's record; a Write through a symlink; another session writing in the
# same window (the detector alerts, it can't tell who).
#
# A session that is not a twin pays one builtin read, one length test and one
# substring test (input over the cap also pays one grep over the whole of it).
# Every path exits 0.

export LC_ALL=C
CAP=524288
# One bounded read. bash 4.1+ reads a fixed count with buffered I/O (-N) and
# leaves the rest on stdin. Older bash (macOS 3.2) has no -N, and -n reads a
# byte per call; head on a pipe may read past its count (stdio buffers), and
# those bytes would be lost (A-38 D-1). So bash < 4.1 saves the whole input to
# a private temp file first, and reads the cap from the file.
tf=""
if (( BASH_VERSINFO[0] > 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1 ) )); then
  IFS= read -r -d '' -N $((CAP + 1)) in
else
  tf=$(umask 077; mktemp "${TMPDIR:-/tmp}/ovm-guard-in.XXXXXX" 2>/dev/null) || tf=""
  if [ -n "$tf" ]; then
    trap 'rm -f "$tf"' EXIT
    cat > "$tf" 2>/dev/null
    in=$(head -c $((CAP + 1)) < "$tf")
  else
    in=$(head -c $((CAP + 1)))
  fi
fi

event=PreToolUse
case $in in *'"hook_event_name":"PostToolUseFailure"'*|*'"hook_event_name": "PostToolUseFailure"'*) event=PostToolUseFailure ;;
  *'"hook_event_name":"PostToolUse"'*|*'"hook_event_name": "PostToolUse"'*) event=PostToolUse ;; esac

deny() {
  local why=${1//[^A-Za-z0-9 ._:\/()-]/}
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Splinter twins never write team state files (%s). Report the change to your spawner instead."}}\n' "${why:0:200}"
  exit 0
}

# The cap comes before the twin test (A-33 S-3, round 2 ruling; A-38): past the
# cap the input is cut, and agent_type can sit after a huge tool_input. So the
# whole over-cap input is scanned once by one grep that stops at the first
# agent_type key (unescaped quotes: inside a JSON string every quote is
# escaped, so only a real key matches), whatever the field order:
#   - its value names splinter-twin: a twin. PreToolUse is denied (fail
#     closed); PostToolUse is alerted, since its record can't be checked;
#   - no agent_type key (including when reading the input failed before one
#     turned up): a main session. Allowed, the guard is skipped.
# A main session is never refused.
overcap=""
if [ ${#in} -gt $CAP ]; then
  re_at='(^|[^\])"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"'
  if [ -n "$tf" ]; then
    at=$(grep -Eo -m 1 "$re_at" "$tf" 2>/dev/null)
  else
    at=$( { printf '%s' "$in"; cat; } 2>/dev/null | grep -Eo -m 1 "$re_at" 2>/dev/null )
  fi
  case $at in
    *'"agent_type"'*splinter-twin*) ;;
    *) exit 0 ;;
  esac
  if [ "$event" = PreToolUse ]; then
    deny "hook input over the 512 KiB cap"
  fi
  overcap=1
fi
case $in in *splinter-twin*) ;; *) [ -n "$overcap" ] || exit 0 ;; esac

# Minimal JSON reader: top-level fields and tool_input's file_path,
# notebook_path and command. A key name inside a string value is never
# mistaken for a key. Escapes are decoded; \uXXXX below 128 too.
parsed=""
[ -n "$overcap" ] || parsed=$(awk 'BEGIN { RS = "\001" }
  function ws() { while (p <= n && index(" \t\r\n", substr(s, p, 1))) p++ }
  function hex(h,   i, v, c) { v = 0; for (i = 1; i <= 4; i++) { c = index("0123456789abcdef", tolower(substr(h, i, 1))); if (!c) return -1; v = v * 16 + c - 1 } return v }
  # str(MODE): a JSON string at p. MODE 0 skips it, 1 prints it (decoded,
  # line feeds as \002) as it goes, 2 returns it. Runs of plain characters are
  # taken with one substr, and a value is never grown one character at a time,
  # so a long string costs linear time in every awk (A-37 P3).
  function str(mode,   o, c, e, v, d, r, t, k, kb, w) {
    if (substr(s, p, 1) != "\"") { bad = 1; return "" }
    p++; o = ""; w = 64
    while (p <= n) {
      # The next quote or backslash, looked for in a window that doubles while
      # none turns up and shrinks back after one: plain runs cost a few long
      # substr calls, escape-dense text a few short ones.
      t = substr(s, p, w); k = index(t, "\""); kb = index(t, "\\")
      if (kb && (!k || kb < k)) k = kb
      if (!k) {
        if (mode) { if (mode == 1) { gsub(/\n/, "\002", t); printf "%s", t } else o = o t }
        p += length(t); if (w < 65536) w *= 2
        continue
      }
      if (k > 1 && mode) { r = substr(t, 1, k - 1); if (mode == 1) { gsub(/\n/, "\002", r); printf "%s", r } else o = o r }
      p += k - 1; w = 64
      c = substr(s, p, 1)
      if (c == "\"") { p++; return o }
      e = substr(s, p + 1, 1); p += 2
      if (e == "n" || e == "r") d = "\n"; else if (e == "t" || e == "b" || e == "f") d = " "
      else if (e == "u") { v = hex(substr(s, p, 4)); p += 4; d = (v >= 32 && v < 127) ? sprintf("%c", v) : (v == 10 || v == 13 ? "\n" : "?") }
      else d = e
      if (mode == 1) printf "%s", (d == "\n" ? "\002" : d); else if (mode == 2) o = o d
    }
    bad = 1; return o
  }
  function want(path) { return (path ~ /^\/(agent_type|agent_id|tool_name|tool_use_id|cwd|hook_event_name)$/ || path == "/tool_input/file_path" || path == "/tool_input/notebook_path" || path == "/tool_input/command") && !(path in seen) }
  function val(path, depth,   c, k, i, q) {
    if (depth > 64) { bad = 1; return }
    ws(); c = substr(s, p, 1)
    if (c == "{") {
      p++; ws()
      if (substr(s, p, 1) == "}") { p++; return }
      while (!bad && p <= n) {
        ws(); k = str(2); ws()
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
    if (c == "\"") {
      if (want(path)) { seen[path] = 1; printf "%s\t", substr(path, 2); str(1); printf "\n" }
      else str(0)
      return
    }
    q = p; while (p <= n && !index(",}] \t\r\n", substr(s, p, 1))) p++
    if (p == q) { bad = 1; return }
    if (want(path)) { seen[path] = 1; print substr(path, 2) "\t" substr(s, q, p - q) }
  }
  { s = $0; n = length(s); p = 1; bad = 0; val("", 0); ws(); if (bad || p <= n) print "ERR\t1" }' <<< "$in") || parsed=ERR   # an awk that fails is unreadable input, never a pass

agent="" aid="" tool="" tuid="" cwd="" fpath="" cmd="" err=""
nl=$'\n' ctl=$'\002' tab=$'\t' BS='\'
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

if [ -n "$overcap" ]; then
  # Only PostToolUse gets here, and it is registered for Bash alone.
  agent=splinter-twin tool=Bash
  re_cwd='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
  if [[ $in =~ $re_cwd ]]; then cwd=${BASH_REMATCH[1]}; cwd=${cwd//\\\\//}; fi
fi
if [ -n "$err" ]; then
  # Malformed input that names a twin: fail closed for the write tools. With
  # no agent_type key at all it is a main session's, and passes (A-37 P3).
  re_atk='(^|[^\])"agent_type"[[:space:]]*:'
  [[ $in =~ $re_atk ]] || exit 0
  [ "$event" = PreToolUse ] && deny "unreadable hook input"
  exit 0
fi
case $agent in *splinter-twin*) ;; *) exit 0 ;; esac

# ---------------------------------------------------------------- shared
# Team root, CONTRACT 7.1 extended (round 4; A-37 B2): the OUTERMOST folder
# holding a live MISSION_BOARD.md across two walks, the cwd and up to three
# folders above it, then the session's project dir and up to three above it.
# A board whose first line says RETIRED BRIDGE COPY is a pointer the live team
# keeps in every seat folder and never counts (liveboard); with it counted, a
# twin in <seat>/drafts/X whose project dir is the seat got that seat as its
# root and could write another seat's INBOX unseen. Outermost means the widest
# coverage; TARS and /go use the nearest live board instead. With no team root
# the pre-check still runs; only the detector is off (reference/twins.md).
# Sets TROOT with builtins only: on Windows every subshell costs about 80 ms.
liveboard() {
  local l=""
  [ -f "$1/MISSION_BOARD.md" ] || return 1
  IFS= read -r -n 200 l < "$1/MISSION_BOARD.md" 2>/dev/null
  case $l in *'RETIRED BRIDGE COPY'*) return 1 ;; esac
  return 0
}
teamroot() {
  local d n found="" o=$PWD f r p keep
  TROOT="" TROOTS=""
  for d in "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    d=${d//\\//}; d=${d%/}
    [ -n "$d" ] && [ -d "$d" ] || continue
    n=0
    while [ $n -le 3 ]; do
      if liveboard "$d" && CDPATH= cd -P -- "$d" 2>/dev/null; then
        found="$found$PWD"$'\n'; cd -- "$o" 2>/dev/null
      fi
      d="$d/.."; n=$((n + 1))
    done
  done
  # Every live root the two walks found, minus any that sits inside another
  # (A-38 P2: when the walks disagree, both trees are watched). TROOT is the
  # outermost, the shortest path.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    keep=1
    while IFS= read -r p; do
      [ -n "$p" ] && [ "$p" != "$f" ] || continue
      case $f/ in "$p"/*) keep=0; break ;; esac
    done <<EOF
$found
EOF
    case $nl$TROOTS in *"$nl$f$nl"*) keep=0 ;; esac
    [ $keep -eq 1 ] || continue
    TROOTS="$TROOTS$f$nl"
    if [ -z "$TROOT" ] || [ ${#f} -lt ${#TROOT} ]; then TROOT=$f; fi
  done <<EOF
$found
EOF
}

# The hash for the snapshot: sha256 (sha256sum, else shasum -a 256), cksum
# (CRC32 plus size) only as the last fallback.
if command -v sha256sum >/dev/null 2>&1; then HASH="sha256sum"
elif command -v shasum >/dev/null 2>&1; then HASH="shasum -a 256"
else HASH="cksum"; fi

# listing ROOT FILE -> FILE gets one line per candidate under ROOT, from one
# walk: "F <path>" a protected file, "G <path>" a .git (file or folder),
# "D <path>" a claim or ID folder. Pruned by name: .git, node_modules, drafts
# and _claims (TARS's).
listing() {
  find "$1" \( -name node_modules -o -name drafts -o -name _claims \) -prune -o \
    -name .git -prune -exec printf 'G %s\n' {} + -o \
    -type f \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md \
       -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md \
       -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _twin-guard.log \
       -o -path '*/.go-claim/*' -o -path '*/_ids/*' \) -exec printf 'F %s\n' {} + -o \
    -type d \( -path '*/.go-claim/*' -o -path '*/_ids/*' \) -exec printf 'D %s\n' {} + > "$2" 2>/dev/null
}

# The snapshot program (A-25.3; A-33 S-1). Inputs, in order: REF (the call's
# own Pre snapshot, at Post; /dev/null at Pre), PASS ("1": print the files to
# hash; "2": read HASHES and build the record), HASHES ($HASH output), then
# the listing.
#   Repo clones (S-1): a file under a folder that holds a .git is dropped,
#   unless that folder holds a BOOT.md (a seat kept in git, like a seat folder
#   that is its own repo). Then only the .git itself is pruned.
#   Every protected file is hashed on every Pre and every Post (A-37 B1). No
#   file metadata is trusted as proof that a file is unchanged: on NTFS a user
#   program can set the mtime and the ctime back after an edit.
#   mode=pre writes the snapshot to OUT ("root" line, then entries). mode=post
#   prints "C <relpath>" for every entry added, removed or changed since REF.
SNAP='
  function dirn(p) { sub(/\/[^\/]*$/, "", p); return p }
  function base(p) { sub(/^.*\//, "", p); return tolower(p) }
  FILENAME == ref {
    if ($1 == "root") next
    k = $0; sub(/^[^ ]+ /, "", k)
    if ($1 == "dir") rdir[k] = 1; else rh[k] = $1
    next
  }
  pass == 2 && FILENAME == hashes {
    if (substr($0, 1, 1) == "\\") next
    if (ck) { h = $1 ":" $2; p = $0; sub(/^[^ ]+ [^ ]+ /, "", p) }
    else { h = $1; p = $0; sub(/^[^ ]+ [ *]?/, "", p) }
    hh[p] = h; next
  }
  {
    t = substr($0, 1, 1); p = substr($0, 3)
    if (t == "G") { g = dirn(p); if (g != root) git[g] = 1; next }
    if (t != "F" && t != "D") next
    n++; typ[n] = t; ap[n] = p
    if (t == "F" && base(p) == "boot.md") boot[dirn(p)] = 1
  }
  END {
    for (g in git) if (!(g in boot)) pr[g] = 1
    m = 0
    for (i = 1; i <= n; i++) {
      p = ap[i]
      if (index(p, root "/") != 1) continue
      d = dirn(p); skip = 0
      while (length(d) > length(root)) { if (d in pr) { skip = 1; break }; d = dirn(d) }
      if (skip) continue
      rel = substr(p, length(root) + 2)
      if (typ[i] == "D") { m++; ed[m] = "dir " rel; er[m] = rel; ek[m] = "dir"; continue }
      if (pass == 1) { print p; continue }
      h = (p in hh) ? hh[p] : "unreadable"
      m++; ed[m] = h " " rel; er[m] = rel; ek[m] = h
    }
    if (pass == 1) exit
    if (mode == "pre") {
      print "root " root > out
      for (i = 1; i <= m; i++) if (ek[i] != "dir") print ed[i] > out
      for (i = 1; i <= m; i++) if (ek[i] == "dir") print ed[i] > out
      exit
    }
    for (i = 1; i <= m; i++) {
      r = er[i]; seen[r] = 1
      if (ek[i] == "dir") { if (!(r in rdir)) print "C " r }
      else if (!(r in rh) || "" rh[r] != "" ek[i]) print "C " r
    }
    for (r in rh) if (!(r in seen)) print "C " r
    for (r in rdir) if (!(r in seen)) print "C " r
  }'

# snapshot MODE ROOT REF [OUT] -> lists ROOT, hashes every protected file
# found, and runs SNAP; sets SNAPOUT to the program's output.
snapshot() {
  local mode=$1 r=$2 ref=$3 out=${4:-} ck=0 lf="$gdir/$callid.l" hf="$gdir/$callid.h"
  [ "$HASH" = cksum ] && ck=1
  [ -f "$ref" ] || ref=/dev/null
  listing "$r" "$lf"
  # shellcheck disable=SC2086
  awk -v pass=1 -v root="$r" -v ref=/dev/null "$SNAP" /dev/null "$lf" | tr '\n' '\000' | xargs -0 $HASH > "$hf" 2>/dev/null
  SNAPOUT=$(awk -v pass=2 -v mode="$mode" -v root="$r" -v ref="$ref" -v hashes="$hf" -v ck="$ck" \
    -v out="$out" "$SNAP" "$ref" "$hf" "$lf")
  : > "$lf"; : > "$hf"
}

# sanit TEXT -> S: TEXT reduced to [A-Za-z0-9_-], at most 64 characters.
sanit() { S=${1//[^A-Za-z0-9_-]/}; S=${S:0:64}; }
# Per-call records live in a folder the guard creates with mode 700; each call
# gets its own snapshot and marker, keyed by agent_id and tool_use_id. A used
# record is emptied rather than deleted (rm is one more process); records over
# a day old are swept now and then.
gdir="${TMPDIR:-${TMP:-/tmp}}/ovm-twin-guard"
sanit "${aid:-noagent}"; callid=$S; sanit "${tuid:-notool}"; callid="$callid.$S"
sanit "$agent"; s_agent=$S; sanit "$aid"; s_aid=$S; sanit "$tuid"; s_tuid=$S
snapfile="$gdir/$callid.snap"; markfile="$gdir/$callid.ok"
BUDGET=5
now=${EPOCHSECONDS:-$(date +%s)}

alert() { # ROOTS EVENT LINES... -> log each line under each root listed (one
  # per line; none with NOLOG=1), and print them as context
  local roots=$1 ev=$2 ctx="" sep="" msg esc
  shift 2
  for msg in "$@"; do
    [ -n "${NOLOG:-}" ] || logline "$roots" "$msg"
    ctx="$ctx$sep$msg"; sep=$nl
  done
  ctx="$ctx$nl""This twin's result is quarantined until the human or the orchestrator reviews the diff (reference/twins.md). Report this alert to your spawner."
  esc=${ctx//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}; esc=${esc//$'\r'/}; esc=${esc//$'\t'/ }
  esc=$(printf '%s' "$esc" | tr -d '\000-\010\013\014\016-\037')
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$ev" "$esc"
}

# recheck SNAPFILE -> SNAPOUT gets "C <relpath>" for every file the Pre
# record lists whose content changed or which is gone. No walk: only the
# recorded files are hashed, so this is quick however many files a command
# created (A-38 P1).
recheck() {
  local sf=$1 r ck=0 hf="$gdir/$callid.h"
  [ "$HASH" = cksum ] && ck=1
  IFS= read -r r < "$sf"; r=${r#root }
  # shellcheck disable=SC2086
  awk -v r="$r" 'FNR > 1 && $1 != "dir" { p = $0; sub(/^[^ ]+ /, "", p); print r "/" p }' "$sf" |
    tr '\n' '\000' | xargs -0 $HASH > "$hf" 2>/dev/null
  SNAPOUT=$(awk -v r="$r" -v ck="$ck" '
    FILENAME == ARGV[1] { if (FNR == 1 || $1 == "dir") next; k = $0; sub(/^[^ ]+ /, "", k); old[k] = $1; next }
    {
      if (substr($0, 1, 1) == "\\") next
      if (ck) { h = $1 ":" $2; p = $0; sub(/^[^ ]+ [^ ]+ /, "", p) }
      else { h = $1; p = $0; sub(/^[^ ]+ [ *]?/, "", p) }
      if (index(p, r "/") == 1) now[substr(p, length(r) + 2)] = h
    }
    END { for (k in old) if (!(k in now) || "" now[k] != "" old[k]) print "C " k }' "$sf" "$hf")
  : > "$hf"
}

# logline ROOTS MSG -> append MSG to <root>/_twin-guard.log for each root
# listed (one per line; duplicates once).
logline() {
  local ts r seen=$nl
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case $seen in *"$nl$r$nl"*) continue ;; esac
    seen="$seen$r$nl"
    printf '%s agent=%s id=%s tool_use=%s %s\n' "$ts" "$s_agent" "$s_aid" "$s_tuid" "$2" >> "$r/_twin-guard.log" 2>/dev/null
  done <<EOF
$1
EOF
}

# ---------------------------------------------------------------- post: detect
if [ "$event" != PreToolUse ]; then
  [ "$tool" = Bash ] || exit 0
  teamroot; root=$TROOT
  busy="$gdir/$callid.busy"
  [ -d "$gdir" ] && printf 'post %s\n' "$now" > "$busy" 2>/dev/null
  if [ -n "$overcap" ]; then
    alert "$TROOTS" "$event" "TWIN-GUARD ALERT: hook input over the 512 KiB cap; protected files were not checked"
    : > "$busy" 2>/dev/null; exit 0
  fi
  mark="" nroots=""
  if [ -s "$markfile" ]; then { IFS= read -r mark; IFS= read -r nroots; } < "$markfile"; fi
  : > "$markfile" 2>/dev/null
  nroots=${nroots#roots }
  case $nroots in ''|*[!0-9]*) nroots=1 ;; esac
  if [ "$mark" = noroot ]; then
    : > "$snapfile"; : > "$busy"
    # Pre found no team root. If one resolves now, the call ran unwatched, or
    # something rewrote the marker: say so (A-33 S-2).
    [ -n "$root" ] && alert "$TROOTS" "$event" "TWIN-GUARD ALERT: no team root at PreToolUse but one resolves now; protected files were not checked"
    exit 0
  fi
  # The Pre records, one per root; any missing one means something removed it.
  sfs=() sroots="" missing=""
  i=1
  while [ $i -le "$nroots" ] && [ $i -le 16 ]; do
    sf=$snapfile; [ $i -gt 1 ] && sf="$snapfile.$i"
    sr=""; [ -s "$sf" ] && IFS= read -r sr < "$sf"; sr=${sr#root }
    [ -n "$sr" ] && [ -d "$sr" ] && sroots="$sroots$sr$nl"
    if [ "$mark" != "ok $callid" ] || [ -z "$sr" ] || [ ! -d "$sr" ]; then missing=1
    else sfs+=("$sf"); fi
    i=$((i + 1))
  done
  if [ -n "$missing" ]; then
    for sf in ${sfs[@]+"${sfs[@]}"}; do : > "$sf"; done; : > "$snapfile"; : > "$busy"
    alert "$TROOTS$sroots" "$event" "TWIN-GUARD ALERT: snapshot missing for this twin command; protected files were not checked"
    exit 0
  fi
  # 1. Re-hash what Pre recorded, and log any change at once, before the
  #    walk: a command that floods the tree with new files can make the walk
  #    outrun the hook's timeout, and the log keeps what was found (A-38 P1).
  msgs=() seenc=$nl
  for sf in "${sfs[@]}"; do
    recheck "$sf"
    while IFS= read -r rel; do
      case $rel in 'C '?*) ;; *) continue ;; esac
      rel=${rel#C }; seenc="$seenc$rel$nl"
      msgs+=("TWIN-GUARD ALERT: protected file changed during twin command: $rel")
      logline "$root$nl$sroots" "TWIN-GUARD ALERT: protected file changed during twin command: $rel"
    done <<EOF
$SNAPOUT
EOF
  done
  # 2. The full walk, for files added or removed.
  nlog=${#msgs[@]}
  for sf in "${sfs[@]}"; do
    IFS= read -r sr < "$sf"; sr=${sr#root }
    snapshot post "$sr" "$sf"
    while IFS= read -r rel; do
      case $rel in 'C '?*) ;; *) continue ;; esac
      rel=${rel#C }
      case $seenc in *"$nl$rel$nl"*) continue ;; esac
      seenc="$seenc$rel$nl"
      msgs+=("TWIN-GUARD ALERT: protected file changed during twin command: $rel")
    done <<EOF
$SNAPOUT
EOF
    : > "$sf"
  done
  : > "$busy"
  [ ${#msgs[@]} -gt 0 ] || exit 0
  i=$nlog
  while [ $i -lt ${#msgs[@]} ]; do logline "$root$nl$sroots" "${msgs[i]}"; i=$((i + 1)); done
  NOLOG=1 alert "" "$event" "${msgs[@]}"
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
    inbox.md|handoff*.md|boot.md|claude.md|working_with_*.md|mission-complete*.md|gopher_registry.md|mission_board.md|team.db|_twin-guard.log|_claims|.go-claim|_ids|ovm-twin-guard) return 0 ;;
  esac
  return 1
}
# prot PATH -> 0 when PATH names a protected file or runs through a protected
# folder. Backslashes are tried both as separators and as escapes.
prot() {
  local p q
  for q in "${1//\\//}" "${1//\\/}"; do
    p=$q; p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
    case "/$p/" in */_claims/*|*/.go-claim/*|*/_ids/*|*/ovm-twin-guard/*) return 0 ;; esac
    p=${p%/}; pname "${p##*/}" && return 0
  done
  return 1
}
protnames="inbox.md handoff.md handoff-x.md boot.md claude.md working_with_x.md mission-complete.md mission-complete-x.md gopher_registry.md mission_board.md team.db _twin-guard.log _claims .go-claim _ids ovm-twin-guard"
# globhit PATTERN -> 0 when a glob's last part could match a protected name.
globhit() {
  local g=${1//\\//} b name
  b=${g##*/}
  case "/$g/" in */_claims/*|*/.go-claim/*|*/_ids/*|*/ovm-twin-guard/*) return 0 ;; esac
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
re_name='(inbox\.md|handoff[^[:space:];&|<>()/]*\.md|boot\.md|claude\.md|working_with_[^[:space:];&|<>()/]*\.md|mission-complete[^[:space:];&|<>()/]*\.md|gopher_registry\.md|mission_board\.md|team\.db|_twin-guard\.log|\.go-claim|ovm-twin-guard|(^|[^a-z0-9])_ids([/[:space:]]|$)|(^|[^a-z0-9])_claims([/[:space:]]|$))'
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

# qdot -> 0 when "." really starts a simple command (A-37 P3): the command is
# split on ; & | ( ) backticks and newlines only OUTSIDE quotes. Single quotes,
# $'...' (where \' does not close) and double quotes are tracked, a backslash
# outside single quotes escapes the next character, and a $( or backtick inside
# double quotes starts a command. if, while, until and elif are skipped before
# the command word, like the other prefixes. An unclosed quote counts as a ".",
# since it can't be read safely. A quoted " . " (perl's or awk's concatenation)
# is not a source. Run only when the quote-blind split below finds a "." verb.
qdot() {
  local s=$cmd q="" c i n=${#cmd} seg="" j
  for ((i = 0; i <= n; i++)); do
    c=${s:i:1}
    case $q in
      "'") [ "$c" = "'" ] && q=""; seg="$seg$c"; continue ;;
      A) case $c in '\') seg="$seg$c${s:i+1:1}"; i=$((i + 1)) ;; "'") q=""; seg="$seg$c" ;; *) seg="$seg$c" ;; esac; continue ;;
      '"')
        case $c in
          '\') if [ "${s:i+1:1}" = '`' ]; then q=""; i=$((i + 1)); c=';'; else seg="$seg$c${s:i+1:1}"; i=$((i + 1)); continue; fi ;;
          '"') q=""; seg="$seg$c"; continue ;;
          '`') q=""; c=';' ;;
          '$') if [ "${s:i+1:1}" = '(' ]; then q=""; i=$((i + 1)); c=';'; else seg="$seg$c"; continue; fi ;;
          *) seg="$seg$c"; continue ;;
        esac ;;
    esac
    # An escaped backtick inside backticks is a nested command substitution.
    if [ "$c" = '\' ] && [ "${s:i+1:1}" = '`' ]; then i=$((i + 1)); c=';'; fi
    case $c in
      '\') seg="$seg$c${s:i+1:1}"; i=$((i + 1)) ;;
      "'"|'"') q=$c; seg="$seg$c" ;;
      '$') if [ "${s:i+1:1}" = "'" ]; then q=A; seg="$seg\$'"; i=$((i + 1)); else seg="$seg$c"; fi ;;
      ''|';'|'&'|'|'|'('|')'|'`'|$'\n')
        split_words "$seg"; seg=""; j=0
        while [ $j -lt ${#words[@]} ]; do
          case ${words[j]//"$BS"/} in *=*|sudo|command|env|exec|coproc|nohup|time|builtin|do|then|else|if|elif|while|until|'{'|'!') j=$((j+1)) ;; *) break ;; esac
        done
        [ $j -lt ${#words[@]} ] && [ "${words[j]//"$BS"/}" = . ] && return 0 ;;
      *) seg="$seg$c" ;;
    esac
  done
  [ -n "$q" ] && return 0
  return 1
}

# Simple commands: split on ; & | ( ) backticks and newlines.
set -f
segs=${cmd//[;&|()\`]/$'\n'}
while IFS= read -r seg; do
  split_words "$seg"
  [ ${#words[@]} -gt 0 ] || continue
  i=0
  while [ $i -lt ${#words[@]} ]; do
    case ${words[i]//"$BS"/} in *=*|sudo|command|env|exec|coproc|nohup|time|builtin|do|then|else|if|elif|while|until|'{'|'!') i=$((i+1)) ;; *) break ;; esac
  done
  [ $i -lt ${#words[@]} ] || continue
  verb=${words[i]##*[/\\]}; verb=${verb%.[Ee][Xx][Ee]}
  args=("${words[@]:i+1}")
  sn=${seg//\'/}; sn=${sn//\"/}; sn=${sn//\\/}
  smention=0; [[ $sn =~ $re_name ]] && smention=1
  # The command word with quotes (split_words) and backslashes removed, as
  # bash reads it: e\val and \. are eval and . (A-38 P3).
  vs=${words[i]//"$BS"/}; vs=${vs##*/}
  case $vs in eval|source) deny "$vs" ;; .) qdot && deny "$vs" ;; esac
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
if [ ! -d "$gdir" ] || [ ! -O "$gdir" ]; then
  ( umask 077; mkdir -p "$gdir" ) 2>/dev/null; chmod 700 "$gdir" 2>/dev/null
fi
# Now and then, sweep records over a day old (emptied ones included).
[ $((RANDOM % 64)) -eq 0 ] && find "$gdir" -type f -mmin +1440 -exec rm -f {} + 2>/dev/null
teamroot; root=$TROOT

# A check that never finished (A-38 P1). Each call's busy marker says "pre T"
# from its Pre and "post T" from its Post, and Post empties it when done. A
# "post" marker over 15 s old means a Post was cut off (the hook has 10 s); a
# "pre" marker over 11 minutes old means the Post never ran (a Bash call ends
# within 10). Either is reported once, by this twin's next Pre, which is denied
# so the report can't be missed.
unfinished=()
for b in "$gdir/$s_aid".*.busy; do
  [ -s "$b" ] || continue
  st="" t=""; read -r st t < "$b" 2>/dev/null
  case $t in ''|*[!0-9]*) t=0 ;; esac
  age=$(( now - t ))
  if { [ "$st" = post ] && [ $age -gt 15 ]; } || { [ "$st" = pre ] && [ $age -gt 660 ]; }; then
    unfinished+=("TWIN-GUARD ALERT: previous check did not finish (${b##*/}: $st, ${age}s ago); protected files may have changed unseen")
    : > "$b"
  fi
done
if [ ${#unfinished[@]} -gt 0 ]; then
  for m in "${unfinished[@]}"; do logline "$TROOTS" "$m"; done
  why="${unfinished[0]} - report this alert to your spawner; the result is quarantined until the diff is reviewed"
  why=${why//[^A-Za-z0-9 ._:\/(),;-]/}
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${why:0:400}"
  exit 0
fi

if [ -z "$root" ]; then
  printf 'root \n' > "$snapfile"; printf 'noroot\n' > "$markfile"
  exit 0
fi
printf 'pre %s\n' "$now" > "$gdir/$callid.busy"
t0=$SECONDS
i=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  i=$((i + 1)); [ $i -le 16 ] || break
  sf=$snapfile; [ $i -gt 1 ] && sf="$snapfile.$i"
  snapshot pre "$r" /dev/null "$sf"
done <<EOF
$TROOTS
EOF
el=$((SECONDS - t0))
printf 'ok %s\nroots %s\n' "$callid" "$i" > "$markfile"
if [ "$el" -gt "$BUDGET" ]; then
  logline "$TROOTS" "TWIN-GUARD NOTE: detector over budget (${el}s snapshot; budget ${BUDGET}s)"
fi
exit 0
