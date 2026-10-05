#!/usr/bin/env bash
# tests/l1/test_ledger.sh -- rule conservation for the v5 firmware split
# (CONTRACT 1.5 and 7.6, as amended by GAP-2, GAP-5 and GAP-6).
#
# Every normative line of the 4.11 firmware (git show d2913e8:hooks/firmware.md,
# CR stripped) must have exactly one R row in docs/v5/firmware-ledger.tsv, and
# every top-level "## " heading outside code fences one S row. A KERNEL or
# MOVED row's evidence must really appear at its target; a DELETED row must
# cite a finding ID or, for DUPLICATE, a surviving line.
# docs/v5/firmware-ledger.L3.tsv and .L4.tsv override rows by (kind, line),
# L3 then L4. A missing amendment file counts as empty.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l1}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

base=d2913e8
NRE='(MUST|NEVER|ALWAYS|SHALL|[Nn]ever|[Aa]lways|[Mm]ust|[Dd]o not|[Dd]on.t|[Oo]nly|[Rr]efuse)'

t "base firmware readable from git"
if git -C "$repo" show "$base:hooks/firmware.md" 2>/dev/null | tr -d '\r' > "$tmp/fw.md" && [ -s "$tmp/fw.md" ]; then
  pass
else
  fail "git show $base:hooks/firmware.md failed (CI needs fetch-depth: 0)"
  echo "FAIL ${0##*/} ($((ok+no)) cases)"; exit 1
fi

LC_ALL=C grep -nE "$NRE" "$tmp/fw.md" | cut -d: -f1 > "$tmp/rbase"

# Fence-aware top-level headings (CommonMark: indent 0-3, a fence closes
# only on a run of the same character at least as long as the opener).
LC_ALL=C awk '
  function fence(s,   m, c, n) {
    if (s !~ /^ ? ? ?(```|~~~)/) return ""
    sub(/^ +/, "", s); c = substr(s, 1, 1); n = 0
    while (substr(s, n + 1, 1) == c) n++
    return c n
  }
  {
    f = fence($0)
    if (open == "") {
      if (f != "") { open = f; next }
      if ($0 ~ /^## /) print NR
    } else if (f != "" && substr(f, 1, 1) == substr(open, 1, 1) && substr(f, 2) + 0 >= substr(open, 2) + 0) {
      s = $0; sub(/^ +/, "", s); gsub(/[`~ \t]/, "", s)
      if (s == "") open = ""
    }
  }' "$tmp/fw.md" > "$tmp/sbase"

t "base has 189 normative lines"
n=$(wc -l < "$tmp/rbase" | tr -d ' ')
[ "$n" = 189 ] && pass || fail "found $n"
t "base has 20 fence-aware top-level headings"
n=$(wc -l < "$tmp/sbase" | tr -d ' ')
[ "$n" = 20 ] && pass || fail "found $n"

ledger="$repo/docs/v5/firmware-ledger.tsv"
t "ledger exists"
[ -f "$ledger" ] && pass || { fail "missing $ledger"; echo "FAIL ${0##*/} ($((ok+no)) cases)"; exit 1; }

# Normalized text of every possible target, one record per file:
# path<TAB>normalized text. Normalization: strip * ` _, collapse whitespace.
: > "$tmp/targets"
for f in "$repo"/hooks/kernel.md "$repo"/reference/*.md "$repo"/skills/*/SKILL.md "$repo"/agents/*.md; do
  [ -f "$f" ] || continue
  rel=${f#"$repo"/}
  LC_ALL=C awk -v rel="$rel" '
    { gsub(/\r/, ""); buf = buf " " $0 }
    END { gsub(/[*`_]/, "", buf); gsub(/[ \t]+/, " ", buf); sub(/^ /, "", buf); sub(/ $/, "", buf); printf "%s\t%s\n", rel, buf }' "$f" >> "$tmp/targets"
  # aliases comment, verbatim
  tr -d '\r' < "$f" | LC_ALL=C sed -n 's/^<!-- aliases: \(.*\) -->$/\1/p' | head -1 | awk -v rel="$rel" '{ printf "%s\t%s\n", rel, $0 }' >> "$tmp/aliases"
done
[ -f "$tmp/aliases" ] || : > "$tmp/aliases"
tr -d '\r' < "$repo/docs/v5/findings-index.txt" | grep -v '^#' | cut -f1 | grep -v '^$' > "$tmp/findings"

# Effective ledger: base rows, then L3, then L4 overrides by (kind, line).
amend() { # file lane
  if [ -f "$1" ]; then tr -d '\r' < "$1" | grep -v '^#' | grep -v '^$' | awk -F'\t' -v lane="$2" '{ print lane "\t" $0 }'; fi
}
{ tr -d '\r' < "$ledger" | grep -v '^#' | grep -v '^$' | awk -F'\t' '{ print "B\t" $0 }'
  amend "$repo/docs/v5/firmware-ledger.L3.tsv" L3
  amend "$repo/docs/v5/firmware-ledger.L4.tsv" L4
} > "$tmp/all"

LC_ALL=C awk -F'\t' -v rbase="$tmp/rbase" -v sbase="$tmp/sbase" -v targets="$tmp/targets" \
  -v aliases="$tmp/aliases" -v findings="$tmp/findings" -v fw="$tmp/fw.md" '
  function norm(s) { gsub(/[*`_]/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
  function bad(m) { print "  FAIL: " m; errs++ }
  function l3inv(p) { return p ~ /^skills\/(go|dispatch|status|diagnostic|morph|roster|initiative|caveman|overmind|engage)\// || p ~ /^reference\/(activation|team-building|initiative|handoffs|dispatch|twins|board|inboxes)\.md$/ || p == "hooks/kernel.md" || p == "agents/splinter-twin.md" }
  function l4inv(p) { return p ~ /^skills\/(collective|assimilate)\// || p == "reference/collective.md" || p == "reference/gopher.md" }
  BEGIN {
    while ((getline l < rbase) > 0) inR[l] = 1
    while ((getline l < sbase) > 0) inS[l] = 1
    while ((getline l < findings) > 0) fid[l] = 1
    while ((getline l < targets) > 0) { i = index(l, "\t"); tgt[substr(l, 1, i - 1)] = substr(l, i + 1) }
    while ((getline l < aliases) > 0) { i = index(l, "\t"); ali[substr(l, 1, i - 1)] = "; " substr(l, i + 1) "; " }
    n = 0; while ((getline l < fw) > 0) { n++; line[n] = l }
  }
  {
    lane = $1; kind = $2; ln = $3
    if (kind != "R" && kind != "S") { bad("row " NR ": unknown kind " kind); next }
    if (lane == "B" && ((kind, ln) in seen)) bad(kind " " ln ": duplicate row in base ledger")
    seen[kind, ln] = 1
    if (kind == "R" && !(ln in inR)) { bad("R " ln ": not a normative line of the base"); next }
    if (kind == "S" && !(ln in inS)) { bad("S " ln ": not a top-level heading of the base"); next }
    if (lane == "L3" || lane == "L4") {
      if ($4 != "DELETED" && !(lane == "L3" ? l3inv($5) : l4inv($5))) bad(lane " " kind " " ln ": target " $5 " is outside " lane "\047s inventory")
    }
    disp[kind, ln] = $4; tg[kind, ln] = $5; ev[kind, ln] = $6; ex[kind, ln] = $7; src[kind, ln] = lane
  }
  END {
    for (l in inR) if (!(("R", l) in disp)) bad("R " l ": normative line has no ledger row")
    for (l in inS) if (!(("S", l) in disp)) bad("S " l ": heading has no ledger row")
    for (k in disp) {
      split(k, kk, SUBSEP); kind = kk[1]; ln = kk[2]; d = disp[k]; t = tg[k]; e = ev[k]
      if (kind == "R") {
        if (d == "KERNEL" || d == "MOVED") {
          if (d == "KERNEL" && t != "hooks/kernel.md") bad("R " ln ": KERNEL target must be hooks/kernel.md")
          if (d == "MOVED" && t !~ /^(reference\/[a-z0-9-]+\.md|skills\/[a-z0-9-]+\/SKILL\.md|agents\/[a-z0-9-]+\.md)$/) bad("R " ln ": MOVED target " t " not allowed")
          ne = norm(e)
          if (length(ne) < 24) bad("R " ln ": evidence shorter than 24 characters")
          else if (!(t in tgt)) bad("R " ln ": target " t " does not exist")
          else if (index(tgt[t], ne) == 0) bad("R " ln ": evidence not found in " t ": " substr(ne, 1, 60))
          if (d == "KERNEL") nk++; else nm++
        } else if (d == "DELETED") {
          if (t == "DUPLICATE") {
            if (!(("R", e) in disp)) bad("R " ln ": DUPLICATE of " e ", which has no row")
            else if (disp["R", e] == "DELETED") bad("R " ln ": DUPLICATE of " e ", which is itself DELETED")
          } else if (t == "DEAD" || t == "SUPERSEDED" || t == "CONTRADICTION") {
            if (!(e in fid)) bad("R " ln ": finding " e " not in findings-index.txt")
          } else bad("R " ln ": DELETED target " t " is not a disposition")
          nd++
        } else bad("R " ln ": bad disposition " d)
      } else {
        title = line[ln]; sub(/^## /, "", title)
        if (d == "MOVED" || d == "KERNEL") {
          if (e != title) bad("S " ln ": title column does not match the heading")
          if (d == "MOVED" && index(ali[t], "; " title "; ") == 0) bad("S " ln ": " title " missing from the aliases of " t)
          if (d == "KERNEL" && t != "hooks/kernel.md") bad("S " ln ": KERNEL target must be hooks/kernel.md")
        } else if (d == "DELETED") {
          if (t != "DEAD" && t != "DUPLICATE" && t != "SUPERSEDED" && t != "CONTRADICTION") bad("S " ln ": DELETED target " t " is not a disposition")
          if (!(ex[k] in fid)) bad("S " ln ": finding " ex[k] " not in findings-index.txt")
        } else bad("S " ln ": bad disposition " d)
        ns++
      }
    }
    printf "in=%d kernel=%d moved=%d deleted=%d s=%d\n", nk + nm + nd, nk, nm, nd, ns
    exit (errs > 0)
  }' "$tmp/all" > "$tmp/out"
rc=$?
grep -v '^in=' "$tmp/out"
summary=$(grep '^in=' "$tmp/out")
echo "  $summary"

t "every ledger check passes"
[ $rc -eq 0 ] && pass || fail "see failures above"
t "in=189 and kernel+moved+deleted=189"
case "$summary" in "in=189 "*) pass ;; *) fail "$summary" ;; esac
t "S rows = 20"
case "$summary" in *" s=20") pass ;; *) fail "$summary" ;; esac

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
