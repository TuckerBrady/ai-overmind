#!/usr/bin/env bash
# invariant.sh <fold-file>
#
# /consolidate's outcome invariant (CONTRACT 6.8, GAP-44). The fold file
# (CONTRACT 7.9) passes only if nothing a sibling held was lost on the way
# into the anchor's record:
#
#   1. every DECISION's Source is a human turn, user:<uuid>, or an answer
#      the human gave in the AskUserQuestion widget, answer:<uuid> (A-40). A
#      decision the assistant reported ("Tucker said ...") is not one.
#   1b. no DECISION comes from a row that carried an unknown tag (A-41): its
#      quoted text holds no <tag> other than the slash-command tags, and its
#      Source is not listed under the optional ## Unknown tags section
#      (rows "| <uuid> | <tags> |", copied from tail.sh's unknown-tag-row
#      lines).
#   2. every Inventory item of kind DECISION appears in the Merged record.
#   3. every Inventory item of kind QUESTION appears in the Merged record.
#   4. for DECISION and QUESTION, the Inventory row count equals the Merged
#      row count.
#   5. every item in a CONFLICT (the row and the item it names) appears under
#      ## Conflicts.
#
# Also checked: the required headings exist, Merged statuses are CURRENT,
# SUPERSEDED-BY <Item> or CONFLICT <Item>, and the Item they name exists.
#
# Exit 0 when every check holds. Exit 1 with one line per failure otherwise.
# Exit 2 on bad usage or an unreadable file. The skill MUST NOT close on a
# non-zero exit.
set -u
f=${1:-}
if [ -z "$f" ] || [ ! -f "$f" ] || [ ! -r "$f" ]; then
  echo "usage: invariant.sh <fold-file>  (no such file)" >&2
  exit 2
fi

tr -d '\r' < "$f" | LC_ALL=C awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function bad(msg) { print "invariant: " msg; FAILED = 1 }
# Split a table row into its cells. The last column may hold "|" itself, so
# columns past (ncol - 1) are joined back into the last one.
function cells(line, ncol, out,   n, parts, i, last) {
  sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
  n = split(line, parts, "|")
  for (i = 1; i < ncol && i <= n; i++) out[i] = trim(parts[i])
  last = ""
  for (i = ncol; i <= n; i++) last = last (i > ncol ? "|" : "") parts[i]
  out[ncol] = trim(last)
  return n
}
# Item = <sib8|anchor>-<D|Q|P|A|U|I><n> (CONTRACT 7.9). Checked before an
# item is ever used inside a regex below.
function okitem(s) { return s ~ /^[A-Za-z0-9]+-[DQPAUI][0-9]+$/ }
function isuuid(u,   d) {
  if (length(u) != 36 || u !~ /^[0-9a-f-]+$/) return 0
  d = substr(u, 9, 1) substr(u, 14, 1) substr(u, 19, 1) substr(u, 24, 1)
  if (d != "----") return 0
  gsub(/-/, "", u)
  return length(u) == 32
}
NR == 1 && /^# CONSOLIDATE / { HEAD = 1 }
/^ANCHOR: / { ANCHOR = 1 }
/^## / {
  sec = trim(substr($0, 4)); SEEN[sec] = 1; hdr = 0; next
}
sec == "Conflicts" { CONF = CONF " " $0 " "; next }
sec == "Unknown tags" && /^[ \t]*\|/ {
  if ($0 ~ /^[ \t]*\|[ \t:|-]+\|[ \t]*$/) next
  cells($0, 2, c); if (isuuid(c[1])) UNK[c[1]] = c[2]
  next
}
/^[ \t]*\|/ {
  if (sec != "Inventory in" && sec != "Merged record") next
  if ($0 ~ /^[ \t]*\|[ \t:|-]+\|[ \t]*$/) next          # the |---| rule
  if (!hdr) { hdr = 1; next }                            # the header row
  if (sec == "Inventory in") {
    cells($0, 5, c)
    item = c[1]; kind = c[2]; src = c[3]
    if (!okitem(item)) { bad("malformed Inventory item: \"" item "\""); next }
    NI++; IKIND[item] = kind; ISRC[item] = src
    if (kind == "DECISION" || kind == "QUESTION") { ICOUNT[kind]++; IORDER[++NIO] = item }
    if (kind == "DECISION") {
      sid = src; sub(/^(user|answer):/, "", sid)
      if (src !~ /^(user|answer):/ || !isuuid(sid))
        bad("DECISION " item " is not sourced from a human turn (Source " src "; want user:<uuid> or answer:<uuid>)")
      else DSRC[item] = sid
      t = c[5]
      while (match(t, /<[A-Za-z][A-Za-z0-9_-]*/)) {
        nm = tolower(substr(t, RSTART + 1, RLENGTH - 1)); t = substr(t, RSTART + RLENGTH)
        if (nm != "command-name" && nm != "command-message" && nm != "command-args") {
          bad("DECISION " item " quotes a row carrying the unknown tag <" nm ">; ask it as a question instead"); break
        }
      }
    }
  } else {
    cells($0, 4, c)
    item = c[1]; kind = c[2]; st = c[3]
    if (!okitem(item)) { bad("malformed Merged item: \"" item "\""); next }
    NM++; MKIND[item] = kind; MST[item] = st; MORDER[NM] = item
    if (kind == "DECISION" || kind == "QUESTION") MCOUNT[kind]++
  }
}
END {
  if (!HEAD) bad("malformed: line 1 is not \"# CONSOLIDATE <ID> <YYYYMMDD-HHMM>\"")
  if (!ANCHOR) bad("malformed: no ANCHOR: line")
  split("Siblings|Inventory in|Merged record|Conflicts|Close", need, "|")
  for (i = 1; i <= 5; i++) if (!(need[i] in SEEN)) bad("malformed: no ## " need[i] " section")
  for (i = 1; i <= NIO; i++) {
    it = IORDER[i]
    if (!(it in MKIND)) {
      if (IKIND[it] == "DECISION") bad("decision missing from Merged: " it)
      else bad("question missing from Merged: " it)
    } else if (MKIND[it] != IKIND[it]) bad("kind changed in Merged: " it " (" IKIND[it] " -> " MKIND[it] ")")
  }
  split("DECISION QUESTION", ks, " ")
  for (k = 1; k <= 2; k++) {
    kk = ks[k]
    if ((ICOUNT[kk] + 0) != (MCOUNT[kk] + 0))
      bad("count mismatch for " kk ": Inventory " (ICOUNT[kk] + 0) ", Merged " (MCOUNT[kk] + 0))
  }
  for (j = 1; j <= NM; j++) {
    it = MORDER[j]; st = MST[it]
    if (st == "CURRENT") continue
    if (st ~ /^SUPERSEDED-BY [^ ]+$/ || st ~ /^CONFLICT [^ ]+$/) {
      ref = st; sub(/^[^ ]+ /, "", ref)
      if (!okitem(ref) || !(ref in MKIND)) { bad("status of " it " names an unknown item: " ref); continue }
      if (st ~ /^CONFLICT /) {
        if (CONF !~ ("[^A-Za-z0-9-]" it "[^A-Za-z0-9-]"))
          bad("CONFLICT " it " absent from ## Conflicts")
        if (CONF !~ ("[^A-Za-z0-9-]" ref "[^A-Za-z0-9-]"))
          bad("CONFLICT " it " names " ref ", which is absent from ## Conflicts")
      }
      continue
    }
    bad("bad status for " it ": \"" st "\" (want CURRENT, SUPERSEDED-BY <Item> or CONFLICT <Item>)")
  }
  for (it in DSRC) if (DSRC[it] in UNK)
    bad("DECISION " it " cites " DSRC[it] ", a row listed under ## Unknown tags (" UNK[DSRC[it]] "); ask it as a question instead")
  if (FAILED) exit 1
  print "invariant: ok (decisions " (ICOUNT["DECISION"] + 0) ", questions " (ICOUNT["QUESTION"] + 0) ", merged rows " (NM + 0) ")"
  exit 0
}'
