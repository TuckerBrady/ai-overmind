#!/usr/bin/env bash
# L2 2.8 (TARS-10, GAP-10): the bash 3.2 lint flags every construct in its
# list, skips comments and the EPOCHSECONDS fallback form, flags the d2913e8
# tars.sh, and passes the current tree. The constructs live in fixtures/*.txt
# so that this file is not itself a hit.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

mk() { mkdir -p "$tmp/$1/tests/lint"; cp "$repo/tests/lint/bash32.sh" "$repo/tests/lint/bash32.patterns" "$tmp/$1/tests/lint/"; }
lint() { "$B" "$tmp/$1/tests/lint/bash32.sh"; }

i=0
while IFS= read -r c || [ -n "$c" ]; do
  c=${c%"$cr"}; [ -n "$c" ] || continue
  i=$(( i + 1 )); mk "c$i"
  printf '#!/usr/bin/env bash\n%s\n' "$c" > "$tmp/c$i/x.sh"
  out=$(lint "c$i")
  t "flags: $c"
  case $out in *"x.sh:2: "*) pass ;; *) fail "not flagged: $out" ;; esac
done < "$here/fixtures/bash32_bad.txt"
t "every listed construct was tried"
expect "only $i" test "$i" -ge 17

mk ok
while IFS= read -r c || [ -n "$c" ]; do printf '%s\n' "${c%"$cr"}"; done < "$here/fixtures/bash32_good.txt" > "$tmp/ok/x.sh"
t "comments and the epoch-variable fallback form pass"
expect "got: $(lint ok)" lint ok

mk old
git -C "$repo" show d2913e8:hooks/tars.sh > "$tmp/old/tars.sh" 2>/dev/null
out=$(lint old)
t "positive control: the d2913e8 tars.sh is flagged"
case $out in *"tars.sh:"*) pass ;; *) fail "got: $out" ;; esac

t "the current tree passes (and the lint does not flag itself)"
expect "got: $("$B" "$repo/tests/lint/bash32.sh")" "$B" "$repo/tests/lint/bash32.sh"

finish
