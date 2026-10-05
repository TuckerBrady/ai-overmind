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
# Read a JSON string starting at P (on the opening quote). Returns the raw,
# still-escaped content and leaves P after the closing quote.
function rstr(   start, rest, q, k, bs) {
  P++; start = P
  while (1) {
    rest = substr(S, P)
    q = index(rest, "\"")
    if (q == 0) { P = L + 1; BAD = 1; return "" }
    k = P + q - 2; bs = 0
    while (k >= start && substr(S, k, 1) == "\\") { bs++; k-- }
    P = P + q
    if (bs % 2 == 0) return substr(S, start, P - 1 - start)
  }
}
function want(path) {
  return path ~ /^(type|uuid|timestamp|isMeta|isSidechain|origin\.kind|message\.role|message\.content|message\.content\[[0-9]+\]\.(type|text))$/
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
      key = rstr(); skipws()
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
  if (c == "\"") {
    if (want(path)) { V[path] = rstr(); T[path] = "s" } else rstr()
    return
  }
  start = P
  while (P <= L) {
    c = substr(S, P, 1)
    if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\r" || c == "\n") break
    P++
  }
  if (want(path)) { V[path] = substr(S, start, P - start); T[path] = "l" }
}
# \n and \t escapes become a space; every other escape is left as written.
function unesc(s,   out, i, c, d) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c != "\\") { out = out c; continue }
    d = substr(s, i + 1, 1)
    if (d == "n" || d == "t") out = out " "
    else out = out c d
    i++
  }
  return out
}
# Remove every harness-injected block from a human turn: <tag ...>...</tag>.
# An unclosed block is cut to the end of the text, so nothing after a
# harness opening tag can pass as words the human typed. The tags were found on
# real human-origin records (2026-10): system-reminder,
# artifact-view-context, local-command-stdout. The others are other harness
# injections. <command-name>, <command-message> and <command-args>
# record the slash command the human typed and stay.
function harness(s,   k, tag, i, c, rest, j, endtag) {
  for (k = 1; k <= NH; k++) {
    tag = HT[k]
    while ((i = index(s, "<" tag)) > 0) {
      c = substr(s, i + length(tag) + 1, 1)
      if (c != ">" && c != " " && c != "/" && c != "\\") {
        # a longer tag name that merely starts the same: step past it
        s = substr(s, 1, i) "" substr(s, i + 1); continue
      }
      rest = substr(s, i)
      endtag = "</" tag ">"
      j = index(rest, endtag)
      if (j == 0) s = substr(s, 1, i - 1)
      else s = substr(s, 1, i - 1) " " substr(rest, j + length(endtag))
    }
  }
  gsub(//, "", s)
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
  NH = split("system-reminder artifact-view-context local-command-stdout local-command-stderr local-command-caveat user-prompt-submit-hook ide_opened_file ide_selection ide_diagnostics task-notification cross-session-message agent-message", HT, " ")
  LS = sprintf("%c%c%c", 226, 128, 168); PS = sprintf("%c%c%c", 226, 128, 169)
  C1 = sprintf("%c", 194) "[" sprintf("%c", 128) "-" sprintf("%c", 159) "]"
}
{
  S = $0
  # Pasted images ride inside user turns as base64; drop the payload, keep the turn.
  if (length(S) > 65536) gsub(/"data": ?"[A-Za-z0-9+\/=]+"/, "\"data\":\"\"", S)
  if (length(S) > 1048576) { SKIP++; next }
  L = length(S); P = 1; BAD = 0
  split("", V); split("", T)
  rval("", 0)
  if (BAD) next
  ty = V["type"]
  if (ty != "user" && ty != "assistant") next
  if (V["isSidechain"] == "true" || V["isMeta"] == "true") next
  if (V["message.role"] != ty) next
  text = ""; other = 0
  if (T["message.content"] == "s") text = V["message.content"]
  else {
    for (i = 0; ("message.content[" i "].type") in V; i++) {
      bt = V["message.content[" i "].type"]
      if (bt == "text") text = text (text == "" ? "" : " ") V["message.content[" i "].text"]
      else if (bt != "image") other = 1
    }
    if (ty == "user" && other) next
  }
  if (text == "") next
  if (ty == "user") {
    if ("origin.kind" in V) { if (V["origin.kind"] != "human") next }
    else if (text ~ /^(<task-notification>|<cross-session-message|<agent-message|Another Claude session|<local-command|\[Request interrupted)/) next
    # The harness appends its own blocks to a human record. Only what the
    # human typed may stand as words of the human.
    text = harness(text)
  }
  out = clean(unesc(text))
  gsub(/^[ ]+|[ ]+$/, "", out)
  if (out == "") next
  u = V["uuid"]; if (!isuuid(u)) u = "-"
  ts = V["timestamp"]; if (ts !~ /^[0-9T:.Z+-]+$/) ts = "-"
  print u "\t" ty "\t" ts "\t" out
}' | tail -n "$n"
echo "--- END ---"
exit 0
