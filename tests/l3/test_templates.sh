#!/usr/bin/env bash
# tests/l3/test_templates.sh -- every handoff template carries the v5 header
# (CONTRACT 4.1.4, 7.2; RUBRIC L3.2 as amended). A handoff template is a fenced
# code block (``` or ~~~, fence length honored) that contains a "Next Steps"
# heading or a line that is exactly ACTIVATION. A compliant template has the
# plain header lines TYPE:, SEAT:, MISSION: and WRITTEN:, and claim.sh's header
# parser reads all four from it.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# Extract each template to $tmp/tpl/<n>.md, recording its source in $tmp/tpl/<n>.src.
mkdir -p "$tmp/tpl"
n=0
for f in "$repo"/reference/*.md "$repo"/skills/*/SKILL.md; do
  tr -d '\r' < "$f" | LC_ALL=C awk -v out="$tmp/tpl" -v src="${f#"$repo"/}" -v start="$n" '
    function fence(s,   c, k) {
      if (s !~ /^ ? ? ?(```|~~~)/) return ""
      sub(/^ +/, "", s); c = substr(s, 1, 1); k = 0
      while (substr(s, k + 1, 1) == c) k++
      return c k
    }
    BEGIN { n = start }
    {
      f = fence($0)
      if (open == "") {
        if (f != "") { open = f; body = ""; first = NR }
        next
      }
      if (f != "" && substr(f, 1, 1) == substr(open, 1, 1) && substr(f, 2) + 0 >= substr(open, 2) + 0) {
        s = $0; sub(/^ +/, "", s); gsub(/[`~ \t]/, "", s)
        if (s == "") {
          if (body ~ /(^|\n)#+ [^\n]*[Nn][Ee][Xx][Tt] [Ss][Tt][Ee][Pp][Ss]/ || body ~ /(^|\n)[ \t]*ACTIVATION[ \t]*(\n|$)/) {
            n++; printf "%s", body > (out "/" n ".md"); close(out "/" n ".md")
            print src ":" first > (out "/" n ".src"); close(out "/" n ".src")
          }
          open = ""; next
        }
      }
      body = body $0 "\n"
    }
    END { print n > (out "/count") }'
  n=$(cat "$tmp/tpl/count")
done

. "$repo/skills/go/header.sh"
templates=$n; compliant=0
i=1
while [ $i -le $n ]; do
  ok_fields=1
  for k in TYPE SEAT MISSION WRITTEN; do
    grep -q "^$k: " "$tmp/tpl/$i.md" || ok_fields=0
  done
  hdr_parse "$tmp/tpl/$i.md"
  [ -n "$HDR_TYPE" ] && [ -n "$HDR_SEAT" ] && [ -n "$HDR_MISSION_RAW" ] && [ -n "$HDR_WRITTEN" ] || ok_fields=0
  if [ $ok_fields -eq 1 ]; then compliant=$((compliant+1)); else echo "  non-compliant template at $(cat "$tmp/tpl/$i.src")"; fi
  i=$((i+1))
done
echo "  templates=$templates compliant=$compliant"

t "at least one handoff template exists"
[ $templates -ge 1 ] && pass || fail "templates=$templates"
t "every handoff template carries TYPE, SEAT, MISSION and WRITTEN"
[ $compliant -eq $templates ] && pass || fail "templates=$templates compliant=$compliant"

t "the dispatch template's header is TYPE: DISPATCH with DISPATCHED BY"
d=$(grep -l '^TYPE: DISPATCH$' "$tmp/tpl/"*.md | head -1)
[ -n "$d" ] && grep -q '^DISPATCHED BY: ' "$d" && pass || fail "no dispatch template"
t "the session handoff template is TYPE: SELF-HANDOFF"
grep -l '^TYPE: SELF-HANDOFF$' "$tmp/tpl/"*.md > /dev/null && pass || fail "no self-handoff template"

finish
