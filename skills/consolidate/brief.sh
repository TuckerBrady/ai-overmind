#!/usr/bin/env bash
# brief.sh <fold-file>
#
# /consolidate's spin-up brief check (amendment A-36). The human has been
# away; the fold file's "## Needs you" section is what they are asked, and
# "## Also open (n)" holds the rest. Both are tables:
#
#   | Item | Rank | Text |
#
# Item is a Merged-record item, or two joined by "+" for a CONFLICT pair.
# Rank, highest first: BLOCKING (work is stopped until they answer),
# DEADLINE (due within 7 days), CONFLICT (two of their own decisions
# disagree), QUESTION (asked, not answered), PROMISE (made to them, now due).
#
# Exit 0 only if:
#   - Needs you has at most 2 items;
#   - no item in Also open outranks an item in Needs you, and Needs you is
#     full (2) whenever Also open is not empty;
#   - every item with a CONFLICT status and every QUESTION still CURRENT in
#     the Merged record is listed, in Needs you or in Also open, exactly
#     once (nothing dropped, nothing doubled);
#   - a CONFLICT is never ranked below CONFLICT;
#   - "Also open (n)" states its own row count, and every item listed exists.
# Exit 1 with one line per failure otherwise; 2 on bad usage.
set -u
f=${1:-}
if [ -z "$f" ] || [ ! -f "$f" ] || [ ! -r "$f" ]; then
  echo "usage: brief.sh <fold-file>  (no such file)" >&2
  exit 2
fi

tr -d '\r' < "$f" | LC_ALL=C awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function bad(msg) { print "brief: " msg; FAILED = 1 }
function okitem(s) { return s ~ /^[A-Za-z0-9]+-[DQPAUI][0-9]+$/ }
BEGIN {
  RK["BLOCKING"] = 1; RK["DEADLINE"] = 2; RK["CONFLICT"] = 3; RK["QUESTION"] = 4; RK["PROMISE"] = 5
}
/^## / {
  sec = trim(substr($0, 4)); hdr = 0
  if (sec ~ /^Also open \(/) { ALSOHDR = sec; sec = "Also open" }
  SEEN[sec] = 1; next
}
/^[ \t]*\|/ {
  if ($0 ~ /^[ \t]*\|[ \t:|-]+\|[ \t]*$/) next
  if (!hdr) { hdr = 1; next }
  line = $0; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
  n = split(line, c, "|")
  if (sec == "Merged record") { it = trim(c[1]); MK[it] = trim(c[2]); MS[it] = trim(c[3]); next }
  if (sec != "Needs you" && sec != "Also open") next
  it = trim(c[1]); rk = trim(c[2])
  if (sec == "Needs you") NN++; else NA++
  k = split(it, parts, "+")
  for (i = 1; i <= k; i++) {
    p = trim(parts[i])
    if (!okitem(p)) { bad("malformed item in " sec ": \"" p "\""); continue }
    if (p in WHERE) bad("listed twice: " p)
    WHERE[p] = sec; RANKOF[p] = rk
  }
  if (!(rk in RK)) { bad("unknown rank \"" rk "\" for " it " (want BLOCKING, DEADLINE, CONFLICT, QUESTION or PROMISE)"); next }
  if (sec == "Needs you") { if (maxneed == "" || RK[rk] > maxneed) { maxneed = RK[rk]; maxneedit = it } }
  else { if (minalso == "" || RK[rk] < minalso) { minalso = RK[rk]; minalsoit = it } }
}
END {
  if (!("Needs you" in SEEN)) bad("malformed: no ## Needs you section")
  if (!("Also open" in SEEN)) bad("malformed: no ## Also open (n) section")
  else {
    n = ALSOHDR; sub(/^Also open \(/, "", n); sub(/\).*$/, "", n)
    if (n !~ /^[0-9]+$/ || n + 0 != NA + 0) bad("Also open header says (" n ") but lists " (NA + 0))
  }
  if (NN + 0 > 2) bad("Needs you has " NN " items; at most 2")
  if (NA + 0 > 0 && NN + 0 < 2) bad("Needs you has room for " minalsoit " (" (NN + 0) " of 2 used)")
  if (maxneed != "" && minalso != "" && minalso < maxneed)
    bad("Also open item " minalsoit " outranks Needs you item " maxneedit)
  for (it in MK) {
    open = (MS[it] ~ /^CONFLICT /) || (MK[it] == "QUESTION" && MS[it] == "CURRENT")
    if (open && !(it in WHERE)) bad("dropped: " it " (" MK[it] ", " MS[it] ") is in neither Needs you nor Also open")
    if (MS[it] ~ /^CONFLICT / && (it in WHERE) && (RANKOF[it] in RK) && RK[RANKOF[it]] > RK["CONFLICT"])
      bad("CONFLICT " it " ranked " RANKOF[it] ", below CONFLICT")
  }
  for (it in WHERE) if (!(it in MK)) bad("unknown item " it " (not in ## Merged record)")
  if (FAILED) exit 1
  print "brief: ok (needs you " (NN + 0) ", also open " (NA + 0) ")"
  exit 0
}'
