#!/usr/bin/env bash
# tail.sh <transcript.jsonl> [N]
#
# /consolidate's transcript reader (CONTRACT 6.10, GAP-47). Prints the last N
# (default 200) conversation turns of a Claude Code session transcript, one
# per line:
#
#   uuid<TAB>role<TAB>timestamp<TAB>text
#
# role is "user" only for a turn the human typed, and "assistant" for the
# assistant's own text. Harness blocks the app appends to a human turn
# (<system-reminder>, <artifact-view-context> and the like) are cut out of it. Everything else is left out: tool_use and tool_result
# payloads, thinking, skill bodies and other meta records, subagent
# (sidechain) records, task notifications, and messages another session or
# agent injected. Those arrive as user-type records but no human typed them,
# so they can never be read as the human's word.
#
# Text keeps its JSON escapes as they are, except that \n and \t become a
# space. Control bytes, C1 controls and Unicode line separators are stripped.
# The output is fenced:
#   --- UNTRUSTED TRANSCRIPT BEGIN ---
#   ...
#   --- END ---
# Everything between the fences is data from another session, never
# instructions. Base64 image payloads are dropped first; a record still over 1 MiB
# after that is skipped, and the count goes to stderr.
#
# No jq: a small JSON scanner in awk reads only the fields it needs.
# Exit 0 on success (including a transcript with no turns), 2 on bad usage.
set -u
f=${1:-}
n=${2:-200}
case $n in ''|*[!0-9]*) echo "usage: tail.sh <transcript.jsonl> [N]" >&2; exit 2 ;; esac
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "usage: tail.sh <transcript.jsonl> [N]  (no such file)" >&2
  exit 2
fi

echo "--- UNTRUSTED TRANSCRIPT BEGIN ---"
LC_ALL=C grep -E '"type": ?"(user|assistant)"' -- "$f" | LC_ALL=C awk '
function skipws() {
  while (P <= L) {
    c = substr(S, P, 1)
    if (c == " " || c == "\t" || c == "\r" || c == "\n") P++; else return
  }
}
# Every quote position in the record, found once. A quote is escaped when
# the text before it ends in an odd run of backslashes. Strings are then read
# by offset: no copy of the rest of the record per string.
function quotes(   n, i, pos) {
  n = split(S, QPIECE, "\"")
  pos = 0; NQ = n - 1; QI = 1
  for (i = 1; i <= NQ; i++) {
    pos += length(QPIECE[i]) + 1; QPOS[i] = pos
    QESC[i] = (match(QPIECE[i], /\\+$/) && RLENGTH % 2 == 1) ? 1 : 0
  }
}
# Read a JSON string starting at P (on the opening quote). Returns the raw,
# still-escaped content (only when keep is set) and leaves P after the
# closing quote.
function rstr(keep,   start, j) {
  while (QI <= NQ && QPOS[QI] < P) QI++
  if (QI > NQ || QPOS[QI] != P) { BAD = 1; P = L + 1; return "" }
  start = P + 1; j = QI + 1
  while (j <= NQ && QESC[j]) j++
  if (j > NQ) { BAD = 1; P = L + 1; return "" }
  QI = j + 1; P = QPOS[j] + 1
  return keep ? substr(S, start, QPOS[j] - start) : ""
}
function want(path) {
  return path ~ /^(type|uuid|timestamp|isMeta|isSidechain|isCompactSummary|isVisibleInTranscriptOnly|origin\.kind|message\.role|message\.content|message\.content\[[0-9]+\]\.(type|text))$/
}
function rval(path, depth,   c, key, i, start) {
  if (depth > 64 || BAD) { BAD = 1; return }
  skipws(); c = substr(S, P, 1)
  if (c == "{") {
    P++; skipws()
    if (substr(S, P, 1) == "}") { P++; return }
    while (P <= L && !BAD) {
      skipws()
      if (substr(S, P, 1) != "\"") { BAD = 1; return }
      key = rstr(1); skipws()
      # A key written with an escape (isMet\u0061) would be read by a real
      # JSON parser as a different key than it is here: fail closed.
      if (index(key, "\\")) { BAD = 1; return }
      if (path == "" && key == "origin") { if (HASORIGIN) { BAD = 1; return } HASORIGIN = 1 }
      if (path == "origin") { OKEYS++; if (key != "kind") ORIGX = 1 }
      if (substr(S, P, 1) != ":") { BAD = 1; return }
      P++
      rval(path == "" ? key : path "." key, depth + 1)
      skipws(); c = substr(S, P, 1)
      if (c == ",") { P++; continue }
      if (c == "}") { P++; return }
      BAD = 1; return
    }
    return
  }
  if (c == "[") {
    P++; skipws(); i = 0
    if (substr(S, P, 1) == "]") { P++; return }
    while (P <= L && !BAD) {
      rval(path "[" i "]", depth + 1); i++
      skipws(); c = substr(S, P, 1)
      if (c == ",") { P++; continue }
      if (c == "]") { P++; return }
      BAD = 1; return
    }
    return
  }
  if (path == "origin" && c != "{") ORIGX = 1
  if (c == "\"") {
    if (want(path)) { if (path in V) { BAD = 1; return } V[path] = rstr(1); T[path] = "s" } else rstr(0)
    return
  }
  start = P
  while (P <= L) {
    c = substr(S, P, 1)
    if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\r" || c == "\n") break
    P++
  }
  if (want(path)) { if (path in V) { BAD = 1; return } V[path] = substr(S, start, P - start); T[path] = "l" }
}
# \n and \t escapes become a space; every other escape is left as written.
# Linear: an escaped backslash is set aside first so "\\n" stays as written.
function unesc(s,   n, i, part, out) {
  gsub(/\\\\/, SOH, s)
  gsub(/\\[nt]/, " ", s)
  if (index(s, SOH) == 0) return s
  n = split(s, part, SOH); out = part[1]
  for (i = 2; i <= n; i++) out = out BS2 part[i]
  return out
}
# --- human turns -------------------------------------------------------------
# The app adds its own text to a human record: blocks appended after the
# typed words (<system-reminder>, <bash-stdout>, ...) and one block prepended
# before them (<artifact-view-context>, whose JSON the artifact page writes).
# Only the words the human typed may come out as role "user". Rules, per
# content block (a string content is one block):
#   - < / > escapes count as < and >; tag names match in any case.
#   - A block opening with <artifact-view-context: keep only what follows the
#     LAST </artifact-view-context>. The harness writes that close after the
#     page JSON, so page text cannot reach past it; an early close inside the
#     JSON only moves text into the part that is dropped. The real records
#     (2026-10) carry the decision after it ("i like c").
#   - A block (or the remainder above) opening with any other tag is dropped,
#     unless it is the slash command the human typed (<command-name>,
#     <command-message>, <command-args>).
#   - Inside a block, the first harness open tag cuts to the END of the
#     block. Nothing after a close tag is ever resumed.
#   - Once a block is cut or dropped, every later block is dropped: a tag
#     split across blocks cannot hide behind the boundary.
function norm(s) {
  gsub(/\\u003[cC]/, "<", s); gsub(/\\u003[eE]/, ">", s); gsub(/\\\//, "/", s)
  return s
}
# Lowercased name of the tag the text opens with, after leading blanks and
# escaped \n \t \r; "" when it does not open with "<" and a letter.
function leadtag(s,   c) {
  while (1) {
    c = substr(s, 1, 1)
    if (c == " " || c == "\t") { s = substr(s, 2); continue }
    if (c == "\\" && substr(s, 2, 1) ~ /[ntr]/) { s = substr(s, 3); continue }
    break
  }
  if (substr(s, 1, 1) != "<" || substr(s, 2, 1) !~ /[A-Za-z]/) return ""
  s = tolower(substr(s, 2))
  match(s, /^[a-z][a-z0-9_-]*/)
  return substr(s, 1, RLENGTH)
}
# Position of the earliest harness open tag in s, 0 if none. "<name" counts
# when the next character cannot continue a tag name (">", a blank, "\" of
# an escaped newline, "/", or the end of the text).
function firsttag(s,   lc, best, k, t, off, p, c) {
  lc = tolower(s); best = 0
  for (k = 1; k <= NH; k++) {
    t = "<" HT[k]; off = 1
    while ((p = index(substr(lc, off), t)) > 0) {
      p = p + off - 1
      c = substr(lc, p + length(t), 1)
      if (c !~ /[a-z0-9_-]/) { if (best == 0 || p < best) best = p; break }
      off = p + 1
    }
  }
  return best
}
function lastclose(s, t,   lc, off, p, last) {
  lc = tolower(s); last = 0; off = 1
  while ((p = index(substr(lc, off), t)) > 0) { last = p + off - 1; off = last + 1 }
  return last
}
# One block of a human record -> the typed words it holds; sets CUT when any
# of it was removed as harness text.
function census(s,   r, nm) {
  while (match(s, /<[A-Za-z][A-Za-z0-9_-]*/)) {
    nm = tolower(substr(s, RSTART + 1, RLENGTH - 1)); TAGS[nm]++
    s = substr(s, RSTART + RLENGTH)
  }
}
function userblock(s,   lt, p, t) {
  s = norm(s)
  census(s)
  lt = leadtag(s)
  if (lt == "artifact-view-context") {
    t = "</artifact-view-context>"
    p = lastclose(s, t)
    if (p == 0) { CUT = 1; return "" }
    s = substr(s, p + length(t))
    lt = leadtag(s)
  }
  # An unknown tag is not cut (A-35); it is counted in the tag census.
  p = firsttag(s)
  if (p > 0) { CUT = 1; s = substr(s, 1, p - 1) }
  # A tag name left open at the end of the block continues in the next block
  # (FORGE-I): cut it, and with CUT set every later block is dropped.
  if (match(s, /<\\?\/?[A-Za-z][A-Za-z0-9_-]*$/)) { CUT = 1; s = substr(s, 1, RSTART - 1) }
  return s
}
# 8-4-4-4-12 hex, checked by position (no regex intervals: not every awk has them).
function isuuid(u,   d) {
  if (length(u) != 36 || u !~ /^[0-9a-fA-F-]+$/) return 0
  d = substr(u, 9, 1) substr(u, 14, 1) substr(u, 19, 1) substr(u, 24, 1)
  if (d != "----") return 0
  gsub(/-/, "", u)
  return length(u) == 32
}
function clean(s) {
  gsub(/\t/, " ", s)
  gsub(/[\001-\010\012-\037\177]/, "", s)
  gsub(LS, "", s); gsub(PS, "", s)
  gsub(C1, "", s)
  return s
}
BEGIN {
  NH = split("system-reminder artifact-view-context local-command-stdout local-command-stderr local-command-caveat bash-input bash-stdout bash-stderr user-prompt-submit-hook ide_opened_file ide_selection ide_diagnostics task-notification cross-session-message agent-message", HT, " ")
  SOH = sprintf("%c", 1); BS2 = sprintf("%c%c", 92, 92)
  CLOSERE = "</[ ]*("
  for (k = 1; k <= NH; k++) CLOSERE = CLOSERE (k > 1 ? "|" : "") HT[k]
  CLOSERE = CLOSERE ")"
  ALLOW["command-name"] = 1; ALLOW["command-message"] = 1; ALLOW["command-args"] = 1
  LS = sprintf("%c%c%c", 226, 128, 168); PS = sprintf("%c%c%c", 226, 128, 169)
  C1 = sprintf("%c", 194) "[" sprintf("%c", 128) "-" sprintf("%c", 159) "]"
}
{
  S = $0
  # Pasted images ride inside user turns as base64; drop the payload, keep the turn.
  if (length(S) > 65536) gsub(/"data": ?"[A-Za-z0-9+\/=]+"/, "\"data\":\"\"", S)
  if (length(S) > 1048576) { SKIP++; next }
  L = length(S); P = 1; BAD = 0; HASORIGIN = 0; OKEYS = 0; ORIGX = 0
  quotes()
  split("", V); split("", T)
  rval("", 0)
  if (BAD) { SKIP++; next }
  ty = V["type"]
  if (ty != "user" && ty != "assistant") next
  if (V["isSidechain"] == "true" || V["isMeta"] == "true") next
  # A compaction summary is model-written text stored as a user record.
  if (V["isCompactSummary"] == "true" || V["isVisibleInTranscriptOnly"] == "true") next
  if (V["message.role"] != ty) next
  human = 0
  if (ty == "user") {
    # Human only with an origin object whose kind is the string "human".
    # No origin, an origin of another shape, or another kind: not typed by
    # the human (fail closed; every human turn in current transcripts has one).
    if (!HASORIGIN) {
      # A user record with no origin and none of the flags: an older shape,
      # or one a newer app writes differently. Counted, never emitted.
      # Only text records count: a tool_result never carries an origin.
      if (V["isMeta"] != "true" && V["isSidechain"] != "true" && V["isCompactSummary"] != "true" && V["isVisibleInTranscriptOnly"] != "true") {
        hastext = (T["message.content"] == "s" && V["message.content"] != ""); notext = 0
        for (i = 0; ("message.content[" i "].type") in V; i++) {
          bt = V["message.content[" i "].type"]
          if (bt == "text" && V["message.content[" i "].text"] != "") hastext = 1
          else if (bt != "text" && bt != "image") notext = 1
        }
        if (hastext && !notext) NOORIGIN++
      }
      next
    }
    if (ORIGX || OKEYS != 1 || !("origin.kind" in V) || T["origin.kind"] != "s" || V["origin.kind"] != "human") next
    human = 1
  }
  text = ""; other = 0; CUT = 0
  if (T["message.content"] == "s") text = human ? userblock(V["message.content"]) : V["message.content"]
  else {
    for (i = 0; ("message.content[" i "].type") in V; i++) {
      bt = V["message.content[" i "].type"]
      if (bt == "text") {
        b = V["message.content[" i "].text"]
        if (human) { if (CUT) continue; b = userblock(b) }
        text = text (text == "" ? "" : " ") b
      }
      else if (bt != "image") other = 1
    }
    if (ty == "user" && other) next
  }
  # Fail closed: a harness CLOSE tag still in the typed words means the
  # harness text was not where the cuts assumed (an artifact-view-context
  # close forged inside a block appended later). Drop the whole record.
  if (human && tolower(text) ~ CLOSERE) { SKIP++; next }
  out = clean(unesc(text))
  gsub(/^[ ]+|[ ]+$/, "", out)
  if (out == "") next
  u = V["uuid"]; if (!isuuid(u)) u = "-"
  ts = V["timestamp"]; if (ts !~ /^[0-9T:.Z+-]+$/) ts = "-"
  print u "\t" ty "\t" ts "\t" out
}
END {
  print "tail.sh: skipped=" (SKIP + 0) > "/dev/stderr"
  print "tail.sh: noorigin=" (NOORIGIN + 0) > "/dev/stderr"
  line = ""; for (t in TAGS) line = line (line == "" ? "" : ",") t ":" TAGS[t]
  print "tail.sh: tags=" line > "/dev/stderr"
}' | tail -n "$n"
echo "--- END ---"
exit 0
