#!/usr/bin/env bash
# tests/l1/test_tars_doc.sh -- reference/tars.md documents exactly L2's line
# grammar (CONTRACT 1.6.4, amendment A-11), and every TARS example line in
# reference/tars.md and README.md matches it.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l1}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

gram="$repo/tests/l2/grammar.txt"
t "the L2 grammar exists"
if [ -f "$gram" ]; then pass; else fail "missing $gram"; echo "FAIL ${0##*/} ($((ok+no)) cases)"; exit 1; fi
tr -d '\r' < "$gram" | LC_ALL=C grep -v '^$' > "$tmp/g"

# Fenced blocks of a Markdown file, one file per block: $tmp/<tag>.<n>
blocks() { # file tag
  tr -d '\r' < "$1" | LC_ALL=C awk -v out="$tmp/$2" '
    /^```/ { if (on) { on = 0 } else { on = 1; n++; printf "" > (out "." n) }; next }
    on { print >> (out "." n) }'
}
blocks "$repo/reference/tars.md" tars
blocks "$repo/README.md" readme

t "reference/tars.md carries the grammar verbatim, all 12 lines in order"
found=""
for b in "$tmp"/tars.*; do cmp -s "$b" "$tmp/g" && found=$b; done
[ -n "$found" ] && pass || fail "no fenced block in reference/tars.md equals tests/l2/grammar.txt"

t "every TARS example line in reference/tars.md matches the grammar"
cat "$tmp"/tars.* | LC_ALL=C grep -E '^TARS( \(cue\))?: ' | LC_ALL=C grep -vF '[0-9]' > "$tmp/ex"
bad=$(LC_ALL=C grep -vExf "$tmp/g" "$tmp/ex")
[ -s "$tmp/ex" ] && [ -z "$bad" ] && pass || fail "outside the grammar: $(printf '%s' "$bad" | head -3)"

t "the examples in reference/tars.md cover all 12 line kinds"
miss=0; i=0
while IFS= read -r re; do
  i=$((i+1)); LC_ALL=C grep -qE -- "$re" "$tmp/ex" || { miss=$((miss+1)); echo "    no example for grammar line $i"; }
done < "$tmp/g"
[ $miss -eq 0 ] && pass || fail "$miss kinds without an example"

t "every TARS line quoted in README.md matches the grammar"
cat "$tmp"/readme.* 2>/dev/null | LC_ALL=C grep -E '^TARS( \(cue\))?: ' > "$tmp/rx"
tr -d '\r' < "$repo/README.md" | LC_ALL=C grep -oE '`TARS( \(cue\))?: [^`]*`' | tr -d '`' >> "$tmp/rx"
bad=$(LC_ALL=C grep -vExf "$tmp/g" "$tmp/rx")
[ -s "$tmp/rx" ] && [ -z "$bad" ] && pass || fail "outside the grammar: $(printf '%s' "$bad" | head -3)"

t "README.md does not describe the 4.11 lines"
LC_ALL=C grep -nE 'pushed to|No handoff written this session' "$repo/README.md" "$repo/reference/tars.md" >/dev/null && fail "4.11 wording present" || pass

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
