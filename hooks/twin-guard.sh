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
#   5.1.1 (parallel twins; Tucker's go, 2026-11-23): the root's own
#      _twin-guard.log is append-only to the detector, not an entry (other
#      twins' hooks write it); a cut-off check keeps its record, and the same
#      twin's next Pre settles it, reporting only a real difference; Python
#      package trees are pruned from the walk; a $VARIABLE write target the
#      command gives literal values is checked through them, cd is followed
#      in a plain && chain, and links to protected files are denied.
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
#   - A redirect target containing ` is denied, and one containing $ unless
#     every variable in it reads through to literal values (5.1.1, below);
#     so is one that names, or as a glob can match, a protected file.
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
# the call's record; a Write through a hard link; lines appended to the root's
# log at run time; another session writing in the same window (the detector
# alerts, it can't tell who).
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
    # No temp file: read exactly, a byte per call (slow, but nothing past the
    # cap leaves stdin, so the agent_type scan below still sees the rest and a
    # twin still fails closed; A-44).
    IFS= read -r -d '' -n $((CAP + 1)) in
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
# "D <path>" a claim or ID folder. Pruned by name: .git, node_modules, drafts,
# _claims (TARS's), and Python's package trees (site-packages, __pycache__,
# .venv, venv; 5.1.1): one project's four venvs held 133k of the live team's
# 140k files and made every walk outrun the hook's 10 s timeout.
listing() {
  case ${OSTYPE:-} in
    darwin*|*bsd*)
      find "$1" \( -name node_modules -o -name drafts -o -name _claims -o -name site-packages \
           -o -name __pycache__ -o -name .venv -o -name venv \) -prune -o \
        -name .git -prune -exec printf 'G %s\n' {} + -o \
        \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md \
           -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md \
           -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _twin-guard.log \
           -o -path '*/.go-claim/*' -o -path '*/_ids/*' \) -type f -exec printf 'F %s\n' {} + -o \
        \( -path '*/.go-claim/*' -o -path '*/_ids/*' \) -type d -exec printf 'D %s\n' {} + > "$2" 2>/dev/null ;;
    *)
      # GNU find prints the lines itself: no printf process per batch. Names
      # are tested before types, so a file that matches no name is never
      # stat'ed for its type.
      find "$1" \( -name node_modules -o -name drafts -o -name _claims -o -name site-packages \
           -o -name __pycache__ -o -name .venv -o -name venv \) -prune -o \
        -name .git -printf 'G %p\n' -prune -o \
        \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md \
           -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md \
           -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _twin-guard.log \
           -o -path '*/.go-claim/*' -o -path '*/_ids/*' \) -type f -printf 'F %p\n' -o \
        \( -path '*/.go-claim/*' -o -path '*/_ids/*' \) -type d -printf 'D %p\n' > "$2" 2>/dev/null ;;
  esac
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
#   mode=pre writes the snapshot to OUT ("root" line, then entries, then the
#   "log" line LOGL when set). mode=post prints "C <relpath>" for every entry
#   added, removed or changed since REF.
#   The root's own log, ROOT/_twin-guard.log by exact path, is not an entry:
#   every twin's hook appends to it, so it is checked as append-only instead
#   (logcheck; 5.1.1). A _twin-guard.log anywhere else is an ordinary entry.
SNAP='
  function dirn(p) { sub(/\/[^\/]*$/, "", p); return p }
  function base(p) { sub(/^.*\//, "", p); return tolower(p) }
  FILENAME == ref {
    if ($1 == "root" || $1 == "log") next
    k = $0; sub(/^[^ ]+ /, "", k)
    if ($1 == "dir") rdir[k] = 1; else rh[k] = $1
    next
  }
  # sha256sum escapes a name holding a backslash or a line feed: the line
  # starts with a backslash and the name has \\ and \n. Undo it rather than
  # skip the line, or the file would read as unhashed both times (A-44).
  function unesc(p,   o, i, c) {
    o = ""
    for (i = 1; i <= length(p); i++) {
      c = substr(p, i, 1)
      if (c == "\\") { i++; c = substr(p, i, 1); if (c == "n") c = "\n" }
      o = o c
    }
    return o
  }
  (pre != "" && FILENAME == pre) || (pass == 2 && FILENAME == hashes) {
    e = 0; if (substr($0, 1, 1) == "\\") { e = 1; $0 = substr($0, 2) }
    if (ck) { h = $1 ":" $2; p = $0; sub(/^[^ ]+ [^ ]+ /, "", p) }
    else { h = $1; p = $0; sub(/^[^ ]+ [ *]?/, "", p) }
    if (e) p = unesc(p)
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
      if (p == root "/_twin-guard.log") continue
      d = dirn(p); skip = 0
      while (length(d) > length(root)) { if (d in pr) { skip = 1; break }; d = dirn(d) }
      if (skip) continue
      rel = substr(p, length(root) + 2)
      if (typ[i] == "D") { m++; ed[m] = "dir " rel; er[m] = rel; ek[m] = "dir"; continue }
      if (pass == 1) { if (!(p in hh)) print p; continue }
      h = (p in hh) ? hh[p] : "unreadable"
      m++; ed[m] = h " " rel; er[m] = rel; ek[m] = h
    }
    if (pass == 1) exit
    if (mode == "pre") {
      print "root " root > out
      for (i = 1; i <= m; i++) if (ek[i] != "dir") print ed[i] > out
      for (i = 1; i <= m; i++) if (ek[i] == "dir") print ed[i] > out
      if (logl != "") print "log " logl > out
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

# snapshot MODE ROOT REF [OUT [PREHASHED]] -> lists ROOT, hashes every
# protected file found (except those PREHASHED already holds, the hashes Post
# took a moment earlier), and runs SNAP; sets SNAPOUT to the program's output.
snapshot() {
  local mode=$1 r=$2 ref=$3 out=${4:-} pre=${5:-} ck=0 lf="$gdir/$callid.l" hf="$gdir/$callid.h" logl=""
  [ "$HASH" = cksum ] && ck=1
  [ -f "$ref" ] || ref=/dev/null
  [ -n "$pre" ] && [ -f "$pre" ] || pre=/dev/null
  listing "$r" "$lf"
  # shellcheck disable=SC2086
  awk -v pass=1 -v root="$r" -v ref=/dev/null -v pre="$pre" -v ck="$ck" "$SNAP" /dev/null "$pre" "$lf" | tr '\n' '\000' | xargs -0 -r $HASH > "$hf" 2>/dev/null
  if [ "$mode" = pre ] && phash "$r/_twin-guard.log"; then logl=$PH; fi
  SNAPOUT=$(awk -v pass=2 -v mode="$mode" -v root="$r" -v ref="$ref" -v pre="$pre" -v hashes="$hf" -v ck="$ck" \
    -v out="$out" -v logl="$logl" "$SNAP" "$ref" "$pre" "$hf" "$lf")
  : > "$lf"; : > "$hf"
}

# phash FILE -> PH="<size> <hash of its first size bytes>"; 1 when FILE is not
# a readable file. The size and the hash cover the same bytes even while other
# hooks append to FILE.
phash() {
  local f=$1 sz h
  PH=""
  [ -f "$f" ] || return 1
  sz=$(wc -c < "$f" 2>/dev/null) || return 1
  sz=${sz//[!0-9]/}
  [ -n "$sz" ] || return 1
  # shellcheck disable=SC2086
  h=$(head -c "$sz" "$f" 2>/dev/null | $HASH 2>/dev/null)
  h=${h%% *}
  [ -n "$h" ] || return 1
  PH="$sz $h"
}

# logcheck SNAPFILE -> LOGC="C _twin-guard.log" when the root's log lost or
# changed any byte it held at Pre: shorter now, gone, or a different hash over
# the same first bytes. Growth is every twin hook's appends and never counts
# (5.1.1). With no "log" line, Pre found no log, and any log now is new growth.
logcheck() {
  local sf=$1 r="" l="" k sz h
  LOGC=""
  { IFS= read -r r; while IFS= read -r k; do l=$k; done; } < "$sf"
  r=${r#root }
  case $l in 'log '*) ;; *) return 0 ;; esac
  l=${l#log }; sz=${l%% *}; h=${l#* }
  if phash_n "$r/_twin-guard.log" "$sz" && [ "$PH" = "$h" ]; then return 0; fi
  LOGC="C _twin-guard.log"
}
# phash_n FILE SIZE -> PH=<hash of FILE's first SIZE bytes>; 1 when FILE is
# missing. A FILE shorter than SIZE hashes fewer bytes, so it never matches.
phash_n() {
  local f=$1 n=$2 h
  PH=""
  [ -f "$f" ] || return 1
  case $n in ''|*[!0-9]*) return 1 ;; esac
  # shellcheck disable=SC2086
  h=$(head -c "$n" "$f" 2>/dev/null | $HASH 2>/dev/null)
  PH=${h%% *}
  [ -n "$PH" ]
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

# recheck SNAPFILE HASHFILE -> HASHFILE gets the fresh hashes, SNAPOUT gets "C <relpath>" for every file the Pre
# record lists whose content changed or which is gone. No walk: only the
# recorded files are hashed, so this is quick however many files a command
# created (A-38 P1).
recheck() {
  local sf=$1 r ck=0 hf=$2
  [ "$HASH" = cksum ] && ck=1
  IFS= read -r r < "$sf"; r=${r#root }
  # shellcheck disable=SC2086
  awk -v r="$r" 'FNR > 1 && $1 != "dir" && $1 != "log" { p = $0; sub(/^[^ ]+ /, "", p); print r "/" p }' "$sf" |
    tr '\n' '\000' | xargs -0 -r $HASH > "$hf" 2>/dev/null
  SNAPOUT=$(awk -v r="$r" -v ck="$ck" '
    function unesc(p,   o, i, c) {
      o = ""
      for (i = 1; i <= length(p); i++) {
        c = substr(p, i, 1)
        if (c == "\\") { i++; c = substr(p, i, 1); if (c == "n") c = "\n" }
        o = o c
      }
      return o
    }
    FILENAME == ARGV[1] { if (FNR == 1 || $1 == "dir" || $1 == "log") next; k = $0; sub(/^[^ ]+ /, "", k); old[k] = $1; next }
    {
      e = 0; if (substr($0, 1, 1) == "\\") { e = 1; $0 = substr($0, 2) }
      if (ck) { h = $1 ":" $2; p = $0; sub(/^[^ ]+ [^ ]+ /, "", p) }
      else { h = $1; p = $0; sub(/^[^ ]+ [ *]?/, "", p) }
      if (e) p = unesc(p)
      if (index(p, r "/") == 1) now[substr(p, length(r) + 2)] = h
    }
    END { for (k in old) if (!(k in now) || "" now[k] != "" old[k]) print "C " k }' "$sf" "$hf")
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

# compare PREFIX LOGROOTS SNAPFILE... -> MSGS gets "<PREFIX><relpath>" for
# every protected file that differs from the Pre records. Step 1 re-hashes the
# files each record lists, checks the root's log as append-only, and logs each
# change under LOGROOTS at once, before step 2 walks for files added or
# removed: a command that floods the tree with new files can make the walk
# outrun the hook's timeout, and the log keeps what was found (A-38 P1). NLOG
# is the number of MSGS already logged.
compare() {
  local pfx=$1 lr=$2 sf sr rel seenc=$nl
  shift 2
  MSGS=()
  # The recheck's findings are logged before the log itself is checked: that
  # check costs two more processes, and a Post near its timeout must not lose
  # a finding to it.
  for sf in "$@"; do
    recheck "$sf" "$sf.r"
    while IFS= read -r rel; do
      case $rel in 'C '?*) ;; *) continue ;; esac
      rel=${rel#C }
      case $seenc in *"$nl$rel$nl"*) continue ;; esac
      seenc="$seenc$rel$nl"
      MSGS+=("$pfx$rel")
      logline "$lr" "$pfx$rel"
    done <<EOF
$SNAPOUT
EOF
    logcheck "$sf"
    if [ -n "$LOGC" ]; then
      case $seenc in *"$nl$LOGC$nl"*) ;; *)
        seenc="$seenc${LOGC#C }$nl"; MSGS+=("$pfx${LOGC#C }"); logline "$lr" "$pfx${LOGC#C }" ;;
      esac
    fi
  done
  NLOG=${#MSGS[@]}
  for sf in "$@"; do
    IFS= read -r sr < "$sf"; sr=${sr#root }
    snapshot post "$sr" "$sf" "" "$sf.r"
    while IFS= read -r rel; do
      case $rel in 'C '?*) ;; *) continue ;; esac
      rel=${rel#C }
      case $seenc in *"$nl$rel$nl"*) continue ;; esac
      seenc="$seenc$rel$nl"
      MSGS+=("$pfx$rel")
    done <<EOF
$SNAPOUT
EOF
  done
}

# settle BUSY STATE AGE -> SETTLE: alert lines (one per line), empty when the
# check BUSY stands for can be closed quietly. BUSY is a busy marker of this
# agent's that is stale: its Post was cut off ("post", over 15 s old) or never
# ran ("pre", over 11 minutes). Its Pre records are still whole (Post empties
# them only when done), so the comparison its Post would have made is made now,
# against the files as they are: a protected file that differs is reported
# (A-38 P1 kept), and a clean result closes the check with a NOTE in the log
# instead of a denied call (5.1.1). A record that is gone is still reported.
settle() {
  local b=$1 st=$2 age=$3 bid mk="" nr="" i sf sr srs=() sroots="" gone="" m why
  bid=${b##*/}; bid=${bid%.busy}
  if [ -s "$gdir/$bid.ok" ]; then { IFS= read -r mk; IFS= read -r nr; } < "$gdir/$bid.ok"; fi
  nr=${nr#roots }; case $nr in ''|*[!0-9]*) nr=1 ;; esac
  why="previous check did not finish ($bid.busy: $st, ${age}s ago)"
  SETTLE=""
  case $mk in
    noroot) ;;
    "ok $bid")
      i=1
      while [ $i -le "$nr" ] && [ $i -le 16 ]; do
        sf="$gdir/$bid.snap"; [ $i -gt 1 ] && sf="$sf.$i"
        sr=""; [ -s "$sf" ] && IFS= read -r sr < "$sf"; sr=${sr#root }
        if [ -n "$sr" ] && [ -d "$sr" ]; then srs+=("$sf"); sroots="$sroots$sr$nl"; else gone=1; fi
        i=$((i + 1))
      done ;;
    *) gone=1 ;;
  esac
  # Its own Post may have finished while this one read: then all is done.
  if [ -n "$gone" ] && [ ! -s "$b" ]; then return 0; fi
  if [ -n "$gone" ]; then
    SETTLE="TWIN-GUARD ALERT: $why; its record is gone, protected files may have changed unseen"
    logline "$TROOTS$sroots" "$SETTLE"
  elif [ ${#srs[@]} -gt 0 ]; then
    compare "TWIN-GUARD ALERT: $why; protected file changed since that command started: " "$TROOTS$sroots" "${srs[@]}"
    i=$NLOG
    while [ $i -lt ${#MSGS[@]} ]; do logline "$TROOTS$sroots" "${MSGS[i]}"; i=$((i + 1)); done
    for m in ${MSGS[@]+"${MSGS[@]}"}; do SETTLE="$SETTLE$m$nl"; done
    SETTLE=${SETTLE%"$nl"}
  fi
  [ -n "$SETTLE" ] || logline "$TROOTS$sroots" "TWIN-GUARD NOTE: $why; re-checked from its record, no protected file changed"
  : > "$b"
  for sf in ${srs[@]+"${srs[@]}"}; do : > "$sf"; : > "$sf.r"; done
  : > "$gdir/$bid.ok"
  return 0
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
  # The records stay whole until this check is done (5.1.1): a Post cut off by
  # the hook timeout leaves its busy marker and its records, and this agent's
  # next Pre finishes the comparison from them (settle).
  mark="" nroots=""
  if [ -s "$markfile" ]; then { IFS= read -r mark; IFS= read -r nroots; } < "$markfile"; fi
  nroots=${nroots#roots }
  case $nroots in ''|*[!0-9]*) nroots=1 ;; esac
  if [ "$mark" = noroot ]; then
    : > "$busy"; : > "$snapfile"; : > "$markfile"
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
    : > "$busy"
    for sf in ${sfs[@]+"${sfs[@]}"}; do : > "$sf"; done; : > "$snapfile"; : > "$markfile"
    alert "$TROOTS$sroots" "$event" "TWIN-GUARD ALERT: snapshot missing for this twin command; protected files were not checked"
    exit 0
  fi
  compare "TWIN-GUARD ALERT: protected file changed during twin command: " "$root$nl$sroots" "${sfs[@]}"
  # Done: the marker goes first, so a cut-off clean-up can't read as a check
  # that never finished.
  : > "$busy"
  for sf in "${sfs[@]}"; do : > "$sf"; : > "$sf.r"; done; : > "$markfile"
  [ ${#MSGS[@]} -gt 0 ] || exit 0
  i=$NLOG
  while [ $i -lt ${#MSGS[@]} ]; do logline "$root$nl$sroots" "${MSGS[i]}"; i=$((i + 1)); done
  NOLOG=1 alert "" "$event" "${MSGS[@]}"
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
# ccwds: every folder a relative path in the command may be relative to, one
# per line. The hook's cwd to start; the segment loop below follows cd
# (5.1.1). With none, a relative path is taken as it stands. cwdunknown is set
# once a cd goes somewhere the text doesn't say.
ccwds=$cwd cwdunknown=0
# inwd PATH -> WD: PATH as it reads from each folder in ccwds (one per line);
# PATH itself when it is absolute or ccwds is empty. ~ and ~/ are $HOME.
inwd() {
  local d=${1//\\//} c
  case $d in '~') d=${HOME:-~} ;; '~/'*) [ -n "${HOME:-}" ] && d=$HOME/${d#\~/} ;; esac
  WD=""
  case $d in /*|[A-Za-z]:*) WD=$d; return 0 ;; esac
  [ -n "$ccwds" ] || { WD=$d; return 0; }
  while IFS= read -r c; do
    [ -n "$c" ] && WD="$WD$c/$d$nl"
  done <<EOF
$ccwds
EOF
  WD=${WD%"$nl"}
}
# dirhit PATH -> 0 when PATH, from any folder in ccwds, is a folder (or a link
# or junction to one) that is protected or holds a protected file within three
# levels. A link is followed (find -H, cd -P), so a link to a seat folder
# counts as the seat folder (5.1.1).
dirhit() {
  local p r
  inwd "$1"
  while IFS= read -r p; do
    [ -n "$p" ] && [ -d "$p" ] || continue
    # An 8.3 short name anywhere in the path can alias a protected folder.
    case $p in *~[0-9]*) return 0 ;; esac
    prot "${p%/}" && return 0
    if [ -L "${p%/}" ]; then r=$(cd -P -- "$p" 2>/dev/null && pwd -P) && [ -n "$r" ] && prot "$r" && return 0; fi
    [ -n "$(find -H "$p" -maxdepth 3 \( -iname INBOX.md -o -iname 'HANDOFF*.md' -o -iname BOOT.md -o -iname CLAUDE.md -o -iname 'WORKING_WITH_*.md' -o -iname 'mission-complete*.md' -o -iname GOPHER_REGISTRY.md -o -iname MISSION_BOARD.md -o -iname team.db -o -iname _claims -o -iname .go-claim -o -iname _ids \) -print 2>/dev/null | head -n 1)" ] && return 0
  done <<EOF
$WD
EOF
  return 1
}
# linkhit PATH -> 0 when PATH, from any folder in ccwds, is a symlink or
# junction whose target is protected (5.1.1). The name alone looks harmless.
linkhit() {
  local p r
  inwd "$1"
  while IFS= read -r p; do
    p=${p%/}
    [ -n "$p" ] && [ -L "$p" ] || continue
    r=$(readlink -f -- "$p" 2>/dev/null) || r=$(readlink -- "$p" 2>/dev/null) || r=""
    [ -n "$r" ] && prot "$r" && return 0
  done <<EOF
$WD
EOF
  return 1
}

case $tool in
  Write|Edit|MultiEdit|NotebookEdit)
    [ -n "$fpath" ] && prot "$fpath" && deny "$tool on ${fpath##*[/\\]}"
    [ -n "$fpath" ] && linkhit "$fpath" && deny "$tool through a link to team state"
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

# ---- variables in write targets (5.1.1)
# A target written with $NAME or ${NAME} is read through NAME's values when the
# command itself gives them all: NAME is not in the hook's environment, and
# every place NAME appears in the command is $NAME, ${NAME}, or a literal
# assignment that ends its command (NAME=value standing alone, or right after
# export, local, declare, typeset, readonly, then, do or else). Every value it
# is given, and the empty value it has before any of them runs, is checked as
# the target, whatever order or branch the assignments sit in. A value that
# uses another such variable is read through it the same way. Anything else
# leaves $NAME unread, and the pre-5.1.1 checks apply to the text unchanged
# (dolhit for arguments; a redirect is denied): for NAME in, read NAME,
# ${NAME:-x}, NAME+=, a prefix assignment (NAME=x cmd "$NAME" expands the old
# value), a value with $( ), backticks, quotes, ~ or an escape, an array, and
# any command that mentions IFS (it would change how $NAME splits).
# This replaces "any $ in a target is denied" for those commands, the false
# deny twins hit writing to their own scratch folders through a variable.
re_ref='\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*'
re_ref_a='^(\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*)'
re_ident='^[A-Za-z_][A-Za-z0-9_]*$'
re_cd='^[[:space:]]*(cd|pushd)([[:space:]]|$)'
envnames=""
# varvals NAME -> VV[]: NAME's values (raw text) as above; 1 when unreadable.
varvals() {
  local n=$1 s=$cmd done_="" m g1 g3 pre post b c w v rest after val chk ok re
  VV=()
  [[ $n =~ $re_ident ]] || return 1
  # Names bash or the session sets on its own (cd sets OLDPWD, every command
  # sets _), whatever the command assigns.
  case $n in
    _|PWD|OLDPWD|HOME|PATH|IFS|CDPATH|RANDOM|SRANDOM|SECONDS|LINENO|EPOCH*|PPID|UID|EUID|GROUPS|HOST*|OSTYPE|MACHTYPE|SHLVL|REPLY|OPT*|PIPESTATUS|FUNCNAME|BASH*|COMP*|DIRSTACK|MAPFILE|TMOUT|HIST*|PS[0-9]|SHELLOPTS|BASHOPTS|COLUMNS|LINES|TMPDIR|TEMP|TMP|CLAUDE*) return 1 ;;
  esac
  [ -n "$envnames" ] || envnames=$nl$(compgen -e)$nl
  case $envnames in *"$nl$n$nl"*) return 1 ;; esac
  re="(^|[^A-Za-z0-9_])($n)([^A-Za-z0-9_]|\$)"
  while [[ $s =~ $re ]]; do
    m=${BASH_REMATCH[0]}; g1=${BASH_REMATCH[1]}; g3=${BASH_REMATCH[3]}
    pre=$done_${s%%"$m"*}$g1
    s=$g3${s#*"$m"}; post=$s
    done_=$pre$n
    case $pre in
      *'\$'|*'\${') return 1 ;;
      *'${') [ "${post:0:1}" = '}' ] || return 1; continue ;;
      *'$') continue ;;
    esac
    [ "${post:0:1}" = '=' ] && [ "${post:1:1}" != '=' ] || return 1
    b=$pre
    while :; do case $b in *' '|*"$tab") b=${b%?} ;; *) break ;; esac; done
    ok=0
    case $b in
      ''|*[\;\&\|\{]|*$'\n'|*$'\r') ok=1 ;;
      *'(') c=${b%?}; case $c in *'$'|*'(') ;; *) ok=1 ;; esac ;;
      *) w=${b##*[!A-Za-z]}
         case $w in export|local|declare|typeset|readonly|then|do|else)
           c=${b%"$w"}; case $c in ''|*[\;\&\|\(\{' '$'\t'$'\n']) ok=1 ;; esac ;;
         esac ;;
    esac
    [ $ok -eq 1 ] || return 1
    v=${post:1}
    case ${v:0:1} in
      '"') rest=${v:1}; case $rest in *'"'*) ;; *) return 1 ;; esac
           val=${rest%%'"'*}; after=${rest#*'"'}
           case $val in *'`'*|*"'"*|*'\$'*|*'\\'*|*'\') return 1 ;; esac ;;
      "'") rest=${v:1}; case $rest in *"'"*) ;; *) return 1 ;; esac
           val=${rest%%"'"*}; after=${rest#*"'"}
           case $val in *'$'*|*'"'*) return 1 ;; esac ;;
      *) val=${v%%[[:space:]\;\&\|\(\)\<\>]*}; after=${v:${#val}}
         case $val in *[\"\'\`\\~]*) return 1 ;; esac ;;
    esac
    chk=$val
    while [[ $chk =~ $re_ref ]]; do chk=${chk/"${BASH_REMATCH[0]}"/}; done
    case $chk in *'$'*) return 1 ;; esac
    while :; do case $after in ' '*|"$tab"*) after=${after#?} ;; *) break ;; esac; done
    case $after in ''|[\;\&\|\)\#]*|$'\n'*|$'\r'*) ;; *) return 1 ;; esac
    VV+=("$val")
  done
  # Never assigned here: its value comes from outside the text. Unread.
  [ ${#VV[@]} -gt 0 ] || return 1
  VV+=("")
  return 0
}
# refnames RAW -> RN: the names RAW expands as $NAME or ${NAME}, outside
# single quotes and not escaped, one per line.
refnames() {
  local s=$1 i=0 L=${#1} c q="" t
  RN=""
  while [ $i -lt $L ]; do
    c=${s:i:1}
    if [ "$q" = "'" ]; then [ "$c" = "'" ] && q=""; i=$((i + 1)); continue; fi
    case $c in
      "\\") i=$((i + 2)); continue ;;
      "'") [ -z "$q" ] && q="'" ;;
      '"') if [ "$q" = '"' ]; then q=""; else q='"'; fi ;;
      '$') t=${s:i}
           if [[ $t =~ $re_ref_a ]]; then t=${BASH_REMATCH[0]#\$}; t=${t#\{}; t=${t%\}}; RN="$RN$t$nl"; fi ;;
    esac
    i=$((i + 1))
  done
}
# subst RAW NAME VALUE -> SB: RAW with each $NAME and ${NAME} outside single
# quotes, not escaped, replaced by VALUE.
subst() {
  local s=$1 n=$2 v=$3 o="" i=0 L=${#1} c q="" k=${#2}
  while [ $i -lt $L ]; do
    c=${s:i:1}
    if [ "$q" = "'" ]; then o="$o$c"; [ "$c" = "'" ] && q=""; i=$((i + 1)); continue; fi
    case $c in
      "\\") o="$o${s:i:2}"; i=$((i + 2)); continue ;;
      "'") [ -z "$q" ] && q="'"; o="$o$c" ;;
      '"') if [ "$q" = '"' ]; then q=""; else q='"'; fi; o="$o$c" ;;
      '$')
        if [ "${s:i+1:k+2}" = "{$n}" ]; then o="$o$v"; i=$((i + k + 3)); continue; fi
        if [ "${s:i+1:k}" = "$n" ] && [[ ! ${s:i+1+k:1} =~ [A-Za-z0-9_] ]]; then o="$o$v"; i=$((i + 1 + k)); continue; fi
        o="$o$c" ;;
      *) o="$o$c" ;;
    esac
    i=$((i + 1))
  done
  SB=$o
}
# resolve RAW -> RC[]: RAW with every readable variable replaced by each of its
# values (at most 64 candidates, 4 rounds deep); RC=(RAW) when none is.
resolve() {
  local raw=$1 round=0 c n v more bad=$nl new
  RC=("$raw")
  case $cmd in *IFS*) return 0 ;; esac
  shopt -u nocasematch
  while [ $round -lt 4 ]; do
    more=0
    for c in "${RC[@]}"; do refnames "$c"; [ -n "$RN" ] && break; done
    [ -n "$RN" ] || break
    for n in $RN; do
      case $bad in *"$nl$n$nl"*) continue ;; esac
      if ! varvals "$n"; then bad="$bad$n$nl"; continue; fi
      new=()
      for c in "${RC[@]}"; do
        for v in "${VV[@]}"; do subst "$c" "$n" "$v"; new+=("$SB"); done
      done
      [ ${#new[@]} -le 64 ] || { shopt -s nocasematch; return 0; }
      RC=("${new[@]}"); more=1
    done
    [ $more -eq 1 ] || break
    round=$((round + 1))
  done
  shopt -s nocasematch
  return 0
}
# unq TEXT -> UQ: TEXT with its ' and " removed (split names rejoin).
unq() { UQ=${1//\'/}; UQ=${UQ//\"/}; }

# target RAW [REC]: one write target, as written (quotes kept). A $-variable
# the command gives literal values to is checked through each value (5.1.1).
target() {
  local raw=$1 rec=${2:-0} c part=0
  case $raw in *'`'*) deny "substituted write target" ;; esac
  case $raw in
    *'$'*)
      resolve "$raw"
      for c in "${RC[@]}"; do
        target1 "$c" "$rec" "$raw"
        case $c in *'$'*) part=1 ;; esac
      done
      # Not every variable read through: the target as written gets the
      # pre-5.1.1 checks too, so reading through never loosens them.
      [ $part -eq 1 ] && target1 "$raw" "$rec" "" ;;
    *) target1 "$raw" "$rec" "" ;;
  esac
  return 0
}
# target1 CANDIDATE REC ORIG: the checks for one spelling of a target. ORIG is
# set when CANDIDATE came from a variable: an unquoted expansion splits on
# whitespace, so each piece is checked too.
target1() {
  local t rec=$2 p parts=()
  unq "$1"; t=$UQ
  [ -n "$t" ] || return 0
  case $t in /dev/null|/dev/stdout|/dev/stderr|'&'*) return 0 ;; esac
  case $t in *'`'*) deny "substituted write target" ;; esac
  prot "$t" && deny "write to ${t##*[/\\]}"
  dolhit "$t" && deny "expanded write target"
  case $t in *'*'*|*'?'*|*'['*) globhit "$t" && deny "glob write target" ;; esac
  if [ -n "$3" ]; then
    case $t in *[[:space:]]*)
      read -r -a parts <<< "$t"
      for p in ${parts[@]+"${parts[@]}"}; do
        prot "$p" && deny "write to ${p##*[/\\]}"
        dolhit "$p" && deny "expanded write target"
        case $p in *'*'*|*'?'*|*'['*) globhit "$p" && deny "glob write target" ;; esac
        linkhit "$p" && deny "write through a link to team state"
        [ "$rec" = 1 ] && dirhit "$p" && deny "write to a folder holding team state"
      done ;;
    esac
  fi
  linkhit "$t" && deny "write through a link to team state"
  if [ "$rec" = 1 ] && [ "$cwdunknown" = 1 ]; then
    case ${t//\\//} in /*|[A-Za-z]:*|'~'|'~/'*) ;; *) deny "recursive write to a relative path after a cd the guard cannot read" ;; esac
  fi
  [ "$rec" = 1 ] && dirhit "$t" && deny "write to a folder holding team state"
  return 0
}

# Redirections, anywhere in the command (heredocs and subshells included).
# The target is the whole word, quoted parts and all ("$D"x is one word). A
# target with a $ is denied unless every variable in it reads through to
# literal values (5.1.1); then each value is checked. Links are checked again
# after the segment loop, from every folder the command may cd to.
writes_redirect=0
rlinks=()
rest=$cmd
re_redir='(^|[^0-9&<>])[0-9]*(>>|>[|]|[&]>>|[&]>|>)[[:space:]]*(("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|<>()"'"'"'])+)'
while [[ $rest =~ $re_redir ]]; do
  r=${BASH_REMATCH[3]}; whole=${BASH_REMATCH[0]}
  case $r in *'`'*) deny "redirect to an expanded target" ;; esac
  case $r in
    *'$'*)
      resolve "$r"
      for c in "${RC[@]}"; do unq "$c"; case $UQ in *'$'*|*'`'*) deny "redirect to an expanded target" ;; esac; done
      rlinks+=("${RC[@]}") ;;
    *) rlinks+=("$r") ;;
  esac
  case $r in /dev/null|/dev/stdout|/dev/stderr|'&'*) ;; *) writes_redirect=1 ;; esac
  target "$r"
  rest=${rest#*"$whole"}
done

# split_words STRING -> words[]: whitespace-separated, honoring '...' and
# "..." (a quoted path with spaces stays one word); backslashes kept. rwords[]
# holds the same words as written, quotes kept, for reading variables.
split_words() {
  local s=$1 w="" rw="" q="" c i n have=0
  words=(); rwords=(); n=${#s}
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; else w="$w$c"; fi
      rw="$rw$c"
    else
      case $c in
        "'"|'"') q=$c; have=1; rw="$rw$c" ;;
        ' '|$'\t') [ $have -eq 1 ] && { words+=("$w"); rwords+=("$rw"); w=""; rw=""; have=0; } ;;
        *) w="$w$c"; rw="$rw$c"; have=1 ;;
      esac
    fi
  done
  [ $have -eq 1 ] && { words+=("$w"); rwords+=("$rw"); }
  return 0
}

# cdto RAW -> CDS: every folder a cd to RAW may land in, read from every
# folder in ccwds, one per line. A spelling the text doesn't settle (cd -, a $
# that doesn't read through, ~user) or an empty one (cd "" stays put) adds the
# current folders instead, so what the old rule checked is always still
# checked, and every spelling that does read through is checked as well.
cdto() {
  local c p keep=0
  CDS="" CDUNK=0
  case $1 in *'`'*|-) CDS=$ccwds; CDUNK=1; return 0 ;; esac
  case $1 in *'$'*) resolve "$1" ;; *) RC=("$1") ;; esac
  for c in "${RC[@]}"; do
    unq "$c"
    case $UQ in
      '') keep=1; continue ;;
      *'$'*) keep=1; CDUNK=1; continue ;;
      '~'?*) [ "${UQ:0:2}" = '~/' ] || { keep=1; CDUNK=1; continue; } ;;
    esac
    inwd "$UQ"
    while IFS= read -r p; do [ -n "$p" ] && CDS="$CDS${p%/}$nl"; done <<EOF
$WD
EOF
  done
  [ $keep -eq 1 ] && [ -n "$ccwds" ] && CDS="$CDS$ccwds$nl"
  CDS=${CDS%"$nl"}
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


# eval, source and . (A-47, A-48): a deliberate blunt instrument that reads no
# quotes and no comments. Bash's rules for those were modelled in rounds 2 to 5
# and every model let a real source through, so this scan ignores them: quoted
# or commented text can only cause a false positive, and those only block a
# twin. The text is checked as written, with backslashes removed, and with
# quotes and backslashes removed, so e\val, ev''al, \. and "." count.
#   - source and eval: denied as a standalone word anywhere, a word being
#     bounded by the start or end of the text, whitespace, or one of
#     ; & | ( ) < > ` ' " { }.
#   - . : denied in command position only, so git add ., find . and cp x .
#     pass: at a line start, after ; & | ( { or a backtick, or after one of
#     the words if then do else elif while until ! time command builtin coproc
#     (whitespace allowed between). Assignment and sudo/env/exec prefixes are
#     covered by the per-command check below.
# Residual: a command word built at run time (d=.; $d ./x.sh) is not seen
# here; only the outcome detector covers what such a command writes.
set -f
re_se='(^|[[:space:];&|()<>`'"'"'"{}])(source|eval)([[:space:];&|()<>`'"'"'"{}]|$)'
# copro[c] is the word coproc, spelled so the bash 3.2 lint (which flags the
# bash 4 builtin) doesn't read this pattern as a use of it.
re_dot='(^|[;&|({`]|(^|[[:space:];&|({`])(if|then|do|else|elif|while|until|!|time|command|builtin|copro[c]))[[:space:]]*[.]([[:space:];&|)<>]|$)'
dse=${cmd//\\/}
for v in "$cmd" "$dse" "$norm"; do
  v=${v//$'\n'/;}; v=${v//$'\r'/;}
  if [[ $v =~ $re_se ]]; then deny "${BASH_REMATCH[2]} as a word in the command"; fi
  if [[ $v =~ $re_dot ]]; then deny ". in command position"; fi
done

# Simple commands: split on ; & | ( ) and newlines, as fb649ac did.
# cd (5.1.1): relative paths read from the folders in ccwds. A command that is
# one chain joined only by && (no ; || & ( ) { } backtick or line break
# anywhere) runs each part only when the part before it succeeded, so a cd that
# is a whole part moves the folder for every part after it. Any other cd adds
# its folder to the ones checked, and the hook's cwd stays among them. After a
# cd whose folder the text doesn't give, a recursive write to a relative path
# is denied.
SOH=$'\001' ETX=$'\003'
linear=1
case $cmd in *[\;\(\)\`]*|*'||'*|*$'\n'*|*$'\r'*|*'{ '*|*'{'$'\t'*) linear=0 ;; esac
lt=${cmd//&&/}; case $lt in *'&'*) linear=0 ;; esac
if [ $linear -eq 1 ]; then
  segs="" rest=${cmd//&&/$ETX}$ETX
  while [ -n "$rest" ]; do
    part=${rest%%"$ETX"*}; rest=${rest#*"$ETX"}
    if [[ $part != *'|'* ]] && [[ $part =~ $re_cd ]]; then
      segs="$segs$SOH$part$nl"
    else
      segs="$segs${part//|/$nl}$nl"
    fi
  done
else
  segs=${cmd//[;&|()]/$'\n'}
fi
# segverb SEG -> words, rwords, verb, args, rargs for one simple command; 1
# when it has no command word.
segverb() {
  split_words "$1"
  [ ${#words[@]} -gt 0 ] || return 1
  i=0
  while [ $i -lt ${#words[@]} ]; do
    case ${words[i]} in *=*|sudo|command|env|exec|nohup|time|builtin|do|then|else|'{'|'!') i=$((i+1)) ;; *) break ;; esac
  done
  [ $i -lt ${#words[@]} ] || return 1
  verb=${words[i]##*[/\\]}; verb=${verb%.[Ee][Xx][Ee]}
  args=("${words[@]:i+1}"); rargs=("${rwords[@]:i+1}")
  return 0
}
# cdseg EFF: the cd, pushd or popd segverb just read. EFF=1 moves the folders
# (a sure && link); 0 adds to them. A cd whose folder the text doesn't give
# sets cwdunknown: from then on a recursive write to a relative path is
# denied (it was unchecked before 5.1.1).
cdseg() {
  local cdarg="~"
  [ "$verb" = popd ] && cdarg=-
  for ((k = 0; k < ${#args[@]}; k++)); do
    case ${args[k]} in --) continue ;; -[LPe@]|-[LPe@][LPe@]) continue ;; esac
    cdarg=${rargs[k]}; break
  done
  cdto "$cdarg"
  [ "$CDUNK" = 1 ] && cwdunknown=1
  if [ -n "$CDS" ]; then
    if [ "$1" = 1 ]; then ccwds=$CDS; else ccwds="$ccwds$nl$CDS"; fi
    allcwds="$allcwds$nl$CDS"
  fi
}
allcwds=$ccwds
# Not one sure chain: a loop or a function can run a cd before text that sits
# above it, so every cd anywhere counts from the start.
if [ $linear -eq 0 ]; then
  case $cmd in *cd*|*pushd*|*popd*)
    while IFS= read -r seg; do
      segverb "$seg" || continue
      case $verb in cd|pushd|popd) cdseg 0 ;; esac
    done <<EOF
$segs
EOF
  ;; esac
fi
while IFS= read -r seg; do
  eff=0; case $seg in "$SOH"*) eff=1; seg=${seg#"$SOH"} ;; esac
  segverb "$seg" || continue
  case $verb in cd|pushd|popd) [ $linear -eq 1 ] && cdseg "$eff" ;; esac
  sn=${seg//\'/}; sn=${sn//\"/}; sn=${sn//\\/}
  smention=0; [[ $sn =~ $re_name ]] && smention=1
  case $verb in eval|source|.) deny "$verb" ;; esac
  # A write verb whose arguments hold a command substitution writes to a target
  # nobody can read from the text: denied, backticks like $( (A-44).
  case $verb in
    cp|mv|ln|install|rsync|scp|tee|rm|rmdir|touch|truncate|unlink|shred|chmod|chown|mkdir|dd)
      for a in ${args[@]+"${args[@]}"}; do case $a in *'`'*|*'$('*) deny "$verb with a substituted argument" ;; esac; done ;;
  esac
  rec=0
  for a in ${args[@]+"${args[@]}"}; do case $a in -*[rR]*|--recursive) rec=1 ;; esac; done
  # Targets are passed as written (rargs, quotes kept), so a variable in one
  # can be read through (5.1.1); target unquotes each spelling it checks.
  case $verb in
    cp|mv|ln|install|rsync|scp)
      last="" haslast=0
      for ((k = 0; k < ${#args[@]}; k++)); do
        case ${args[k]} in -*) continue ;; esac
        last=${rargs[k]}; haslast=1
        if [ "$verb" = mv ]; then target "$last" 1; else target "$last"; fi
      done
      [ $haslast -eq 1 ] && target "$last" 1 ;;
    tee|rm|rmdir|touch|truncate|unlink|shred|chmod|chown|mkdir)
      for ((k = 0; k < ${#args[@]}; k++)); do case ${args[k]} in -*) ;; *) target "${rargs[k]}" "$rec" ;; esac; done ;;
    dd)
      for ((k = 0; k < ${#args[@]}; k++)); do case ${args[k]} in of=*) a=${rargs[k]}; target "${a/of=/}" ;; esac; done
      [ $mentions -eq 1 ] && deny "dd naming a protected file" ;;
    sed|gsed|perl*)
      inplace=0
      for a in ${args[@]+"${args[@]}"}; do case $a in -i*|--in-place*|-[a-hj-zA-Z]*i*) inplace=1 ;; esac; done
      if [ $inplace -eq 1 ]; then for ((k = 0; k < ${#args[@]}; k++)); do case ${args[k]} in -*) ;; *) target "${rargs[k]}" ;; esac; done; fi ;;
    find)
      case " ${args[*]} " in
        *' -delete '*|*' -exec'*|*' -ok'*)
          [ $mentions -eq 1 ] && deny "find writing a protected file"
          case " ${args[*]} " in *'`'*|*'$('*) deny "find writing to a substituted name" ;; esac
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
# Redirect targets that are links, from every folder the command may cd to.
ccwds=$allcwds
for r in ${rlinks[@]+"${rlinks[@]}"}; do
  unq "$r"; [ -n "$UQ" ] && linkhit "$UQ" && deny "redirect through a link to team state"
done

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
# within 10). Markers are per agent and per call (<agent_id>.<tool_use_id>),
# and only this agent's own are read: another twin's slow check never touches
# this one. A stale one is settled by this agent's next Pre: the comparison is
# made from its record, and only a protected file that really differs (or a
# record that is gone) is reported, by denying this call so the report can't
# be missed (5.1.1; until then every stale marker was reported and denied).
unfinished=()
for b in "$gdir/${callid%%.*}".*.busy; do
  [ -s "$b" ] || continue
  [ "$b" = "$gdir/$callid.busy" ] && continue
  st="" t=""; read -r st t < "$b" 2>/dev/null
  case $t in ''|*[!0-9]*) t=0 ;; esac
  age=$(( now - t ))
  if { [ "$st" = post ] && [ $age -gt 15 ]; } || { [ "$st" = pre ] && [ $age -gt 660 ]; }; then
    settle "$b" "$st" "$age"
    [ -n "$SETTLE" ] && unfinished+=("$SETTLE")
  fi
done
if [ ${#unfinished[@]} -gt 0 ]; then
  why="${unfinished[0]%%"$nl"*} - report this alert to your spawner; the result is quarantined until the diff is reviewed"
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
