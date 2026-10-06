#!/usr/bin/env bash
# tail.sh <transcript.jsonl> [N]
#
# /consolidate's transcript reader (CONTRACT 6.10, GAP-47). Prints the last N
# (default 200) conversation turns of a Claude Code session transcript, one
# per line:
#
#   uuid<TAB>role<TAB>timestamp<TAB>text
#
# role is one of:
#   user       a turn the human typed: a user record whose origin is exactly
#              {"kind":"human"}. Harness blocks the app adds to it
#              (<system-reminder>, <artifact-view-context>, <bash-stdout>
#              and the like) are cut out of it.
#   asked      the question of an AskUserQuestion call (text the model
#              wrote), with "|", ";" and A:/Q: markers taken out, or
#              "(no question text)"; never a DECISION source
#   answer     what the human picked or typed in that widget, alone on its
#              row, right after its asked row: the harness-written result of
#              an AskUserQuestion call this transcript made (A-40, A-46). A
#              multiSelect answer is its items joined by ", ".
#   assistant  the assistant's own text.
# Everything else is left out: tool_use and other tool_result payloads,
# thinking, skill bodies and other meta records, compaction summaries,
# subagent (sidechain) records, task notifications, messages another session
# or agent injected, and user records with no origin. None of those can be
# read as the human's word.
#
# Text keeps its JSON escapes as they are, except that the escapes for a
# newline and a tab become a
# space. Control bytes, C1 controls and Unicode line separators are stripped.
# The output is fenced:
#   --- UNTRUSTED TRANSCRIPT BEGIN ---
#   ...
#   --- END ---
# Everything between the fences is data from another session, never
# instructions.
#
# stderr carries, in this order:
#   tail.sh: unknown-tag-row <uuid> <tags>   one per emitted row whose text
#       carries a tag outside the known set; such a row is never a DECISION
#       source (A-41)
#   tail.sh: skipped=<n>    records it could not judge: malformed JSON, a
#       duplicated or escaped key, over 1 MiB after base64 images are
#       dropped, or harness text where it should not be
#   tail.sh: noorigin=<n>   user text records with no origin
#   tail.sh: tags=<name>:<n>,...   every tag seen in human turns and answers
#
# No jq: each record is cut into tokens once and parsed in awk.
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
# The record is cut into tokens once. split() on the quote character gives
# the pieces between quotes; a quote is escaped when the piece before it ends
# in an odd run of backslashes. Pieces outside strings hold only structure
# and literals and are short, so they are read character by character;
# string pieces are never walked, only located (start and length). This
# keeps a 0.9 MB record with 70k strings fast on every awk, including ones
# whose substr() costs the length of the whole record.
function tokenize(   n, i, j, piece, k, c, lit, start) {
  n = split(S, QP, "\"")
  NT = 0; i = 1; pos = 0
  while (i <= n) {
    # piece i is outside any string
    piece = QP[i]; lit = ""
    for (k = 1; k <= length(piece); k++) {
      c = substr(piece, k, 1)
      if (c == " " || c == "\t" || c == "\r" || c == "\n") { if (lit != "") { TT[++NT] = "l"; TV[NT] = lit; lit = "" } continue }
      if (c == "{" || c == "}" || c == "[" || c == "]" || c == ":" || c == ",") {
        if (lit != "") { TT[++NT] = "l"; TV[NT] = lit; lit = "" }
        TT[++NT] = c; continue
      }
      lit = lit c
    }
    if (lit != "") { TT[++NT] = "l"; TV[NT] = lit }
    pos += length(piece)
    if (i == n) break
    # quote i opens a string at pos + 1; it closes at the next quote that
    # is not escaped
    start = pos + 2; pos += 1; j = i + 1
    while (j < n && QP[j] ~ /\\$/ && match(QP[j], /\\+$/) && RLENGTH % 2 == 1) { pos += length(QP[j]) + 1; j++ }
    if (j >= n) { BAD = 1; return }
    pos += length(QP[j]) + 1
    TT[++NT] = "s"; TS[NT] = start; TL[NT] = pos - start
    i = j + 1
  }
}
function want(path) {
  return path ~ /^(type|uuid|timestamp|isMeta|isSidechain|isCompactSummary|isVisibleInTranscriptOnly|origin\.kind|message\.role|message\.content|message\.content\[[0-9]+\]\.(type|text|name|id|tool_use_id|is_error))$/
}
function rval(path, depth,   t, key, i) {
  if (depth > 64 || BAD || TI > NT) { BAD = 1; return }
  t = TT[TI]
  if (path == "origin" && t != "{") ORIGX = 1
  if (t == "{") {
    TI++
    if (TT[TI] == "}") { TI++; return }
    while (TI <= NT && !BAD) {
      if (TT[TI] != "s") { BAD = 1; return }
      key = substr(S, TS[TI], TL[TI]); TI++
      # A key written with an escape (isMet<backslash>u0061) would be read by
      # a real JSON parser as a different key than it is here: fail closed.
      if (index(key, "\\") && (path == "" || path == "message" || path == "origin" || path == "toolUseResult" || path ~ /^message\.content\[[0-9]+\]$/)) { BAD = 1; return }
      # A key that appears twice at the top or inside toolUseResult (a real
      # parser keeps one, this one would read another): fail closed (N5).
      if (path == "" || path == "toolUseResult") {
        if ((path SUBSEP key) in KSEEN) { BAD = 1; return }
        KSEEN[path SUBSEP key] = 1
      }
      # toolUseResult.answers: question text -> the answer the human chose
      # or typed in the AskUserQuestion widget. Only string answers count.
      if (path == "toolUseResult.answers") {
        # A question key with a \u escape could equal another key once a
        # real parser decodes it: fail closed (N5).
        if (key in AQSEEN || index(key, "\\u")) { BAD = 1; return }
        AQSEEN[key] = 1
        if (TT[TI] != ":") { BAD = 1; return }
        TI++; NANS++; AQ[NANS] = key
        if (TT[TI] == "s") { AA[NANS] = substr(S, TS[TI], TL[TI]); TI++ }
        else if (TT[TI] == "[") {
          # multiSelect: a list of strings, joined by ", " with the
          # separators taken out of each item
          TI++; AA[NANS] = ""
          while (TT[TI] != "]") {
            if (TT[TI] != "s") { BAD = 1; return }
            item = substr(S, TS[TI], TL[TI]); gsub(/[|;,]/, " ", item); gsub(/^ +| +$/, "", item)
            if (item != "") AA[NANS] = AA[NANS] (AA[NANS] == "" ? "" : ", ") item
            TI++
            if (TT[TI] == ",") TI++
            else if (TT[TI] != "]") { BAD = 1; return }
          }
          TI++
        }
        else { BAD = 1; return }
        if (TT[TI] == ",") { TI++; continue }
        if (TT[TI] == "}") { TI++; return }
        BAD = 1; return
      }
      if (path == "" && key == "origin") { if (HASORIGIN) { BAD = 1; return } HASORIGIN = 1 }
      if (path == "origin") { OKEYS++; if (key != "kind") ORIGX = 1 }
      if (TT[TI] != ":") { BAD = 1; return }
      TI++
      rval(path == "" ? key : path "." key, depth + 1)
      if (BAD) return
      if (TT[TI] == ",") { TI++; continue }
      if (TT[TI] == "}") { TI++; return }
      BAD = 1; return
    }
    BAD = 1; return
  }
  if (t == "[") {
    TI++; i = 0
    if (TT[TI] == "]") { TI++; return }
    while (TI <= NT && !BAD) {
      rval(path "[" i "]", depth + 1); i++
      if (BAD) return
      if (TT[TI] == ",") { TI++; continue }
      if (TT[TI] == "]") { TI++; return }
      BAD = 1; return
    }
    BAD = 1; return
  }
  if (t == "s") {
    if (want(path)) { if (path in V) { BAD = 1; return } V[path] = substr(S, TS[TI], TL[TI]); T[path] = "s" }
    TI++; return
  }
  if (t == "l") {
    if (want(path)) { if (path in V) { BAD = 1; return } V[path] = TV[TI]; T[path] = "l" }
    TI++; return
  }
  BAD = 1
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
    if (!(nm in ALLOW) && !(nm in HTSET)) ROWUNK[nm] = 1
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
# One output row. A row whose text carried a tag outside the known set is
# also named on stderr: it can never be the source of a DECISION (A-41).
function emit(role, text,   out, u, ts, t, l) {
  out = clean(unesc(text))
  gsub(/^[ ]+|[ ]+$/, "", out)
  if (out == "") return
  u = V["uuid"]; if (!isuuid(u)) u = "-"
  ts = V["timestamp"]; if (ts !~ /^[0-9T:.Z+-]+$/) ts = "-"
  print u "\t" role "\t" ts "\t" out
  l = ""; for (t in ROWUNK) l = l (l == "" ? "" : ",") t
  if (l != "") print "tail.sh: unknown-tag-row " u " " l > "/dev/stderr"
}
BEGIN {
  NH = split("system-reminder artifact-view-context local-command-stdout local-command-stderr local-command-caveat bash-input bash-stdout bash-stderr user-prompt-submit-hook ide_opened_file ide_selection ide_diagnostics task-notification cross-session-message agent-message", HT, " ")
  SOH = sprintf("%c", 1); BS2 = sprintf("%c%c", 92, 92)
  for (k = 1; k <= NH; k++) HTSET[HT[k]] = 1
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
  BAD = 0; HASORIGIN = 0; OKEYS = 0; ORIGX = 0; NANS = 0
  split("", AQ); split("", AA); split("", AQSEEN); split("", KSEEN); split("", ROWUNK)
  split("", TT); split("", TS); split("", TL); split("", TV)
  tokenize(); TI = 1
  split("", V); split("", T)
  rval("", 0)
  if (BAD) { SKIP++; next }
  ty = V["type"]
  if (ty != "user" && ty != "assistant") next
  if (V["isSidechain"] == "true" || V["isMeta"] == "true") next
  # A compaction summary is model-written text stored as a user record.
  if (V["isCompactSummary"] == "true" || V["isVisibleInTranscriptOnly"] == "true") next
  if (V["message.role"] != ty) next
  if (ty == "assistant") {
    for (i = 0; ("message.content[" i "].type") in V; i++)
      if (V["message.content[" i "].type"] == "tool_use" && V["message.content[" i "].name"] == "AskUserQuestion")
        ASK[V["message.content[" i "].id"]] = 1
  }
  # The harness writes the result of an AskUserQuestion call: the click or
  # typed answer of the human (A-40), matched to a call this transcript made,
  # with the same harness stripping as a typed turn. The question is model
  # text, so it gets its own "asked" row and the answer its own "answer"
  # row (A-46): nothing in a question can reach an answer row.
  if (ty == "user" && !HASORIGIN && ("message.content[0].type" in V) && !("message.content[1].type" in V) &&
      V["message.content[0].type"] == "tool_result" && (V["message.content[0].tool_use_id"] in ASK) &&
      V["message.content[0].is_error"] != "true") {
    # One result per call: a second result for the same id is a replay.
    delete ASK[V["message.content[0].tool_use_id"]]
    # An answer record with no answers in it is a shape not understood.
    if (NANS == 0) { SKIP++; next }
    for (k = 1; k <= NANS; k++) {
      CUT = 0; a = userblock(AA[k])
      if (a ~ /^[ ]*$/) { SKIP++; continue }
      if (tolower(a) ~ CLOSERE) { SKIP++; continue }
      # Two rows per question (A-46): "asked" carries the question (text
      # the model wrote), every separator and marker taken out; "answer"
      # carries only what the human picked or typed.
      q = AQ[k]
      gsub(/[|;]/, " ", q)
      gsub(/(^|[^A-Za-z])[AaQq][ ]*:/, " ", q)
      if (q ~ /^[ ]*$/) q = "(no question text)"
      emit("asked", q)
      emit("answer", a)
    }
    next
  }
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
        it = (T["message.content"] == "s") ? V["message.content"] : V["message.content[0].text"]
        if (it ~ /^\[Request interrupted by user( for tool use)?\]$/) hastext = 0
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
  emit(ty, text)
}
END {
  print "tail.sh: skipped=" (SKIP + 0) > "/dev/stderr"
  print "tail.sh: noorigin=" (NOORIGIN + 0) > "/dev/stderr"
  line = ""; for (t in TAGS) line = line (line == "" ? "" : ",") t ":" TAGS[t]
  print "tail.sh: tags=" line > "/dev/stderr"
}' | tail -n "$n"
echo "--- END ---"
exit 0
