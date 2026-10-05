#!/usr/bin/env bash
# tests/lint/skills.sh -- static checks over the plugin's Markdown
# (TEST_STRATEGY section 5).
#
# - Every skills/*/SKILL.md has valid frontmatter: line 1 is ---, a closing ---
#   within 40 lines, name: equal to the directory, a non-empty description:,
#   and no tab characters.
# - Over skills/ agents/ reference/ hooks/kernel.md README.md: no emoji, no
#   deleted term (tests/lint/deleted-terms.txt) outside its allow-regex, and
#   every reference/<file> or ../../reference/<file> citation exists.
# - The kernel's Index names every skill directory and every reference file,
#   and every name it lists exists.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/lint}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

# --- frontmatter ------------------------------------------------------------
for f in "$repo"/skills/*/SKILL.md; do
  d=${f%/SKILL.md}; d=${d##*/}
  t "frontmatter $d"
  n=0; sname=""; desc=""; closed=""; tabs=""; pending=""
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}; n=$((n+1))
    if [ $n -eq 1 ]; then
      [ "$line" = "---" ] || break
      continue
    fi
    [ "$line" = "---" ] && { closed=1; break; }
    case $line in *$'\t'*) tabs=1 ;; esac
    case $line in
      name:*) sname=${line#name:}; sname=${sname# }; pending="" ;;
      description:*)
        v=${line#description:}; v=${v# }
        case $v in ''|'>'|'>-'|'|'|'|-') pending=1 ;; *) desc=x; pending="" ;; esac ;;
      " "*) [ -n "$pending" ] && [ -n "${line// /}" ] && desc=x ;;
      *) pending="" ;;
    esac
    [ $n -gt 40 ] && break
  done < "$f"
  if [ -n "$closed" ] && [ "$sname" = "$d" ] && [ -n "$desc" ] && [ -z "$tabs" ]; then
    pass
  else
    fail "closed=${closed:-no} name='$sname' desc=${desc:-empty} tabs=${tabs:-none}"
  fi
done

# --- the scanned set -----------------------------------------------------------
: > "$tmp/files"
for p in "$repo"/skills/*/SKILL.md "$repo"/skills/*/*.md "$repo"/agents/*.md "$repo"/reference/*.md "$repo"/hooks/kernel.md "$repo"/README.md; do
  [ -f "$p" ] && printf '%s\n' "$p" >> "$tmp/files"
done
sort -u "$tmp/files" -o "$tmp/files"
scanset=()
while IFS= read -r p; do scanset+=("$p"); done < "$tmp/files"

t "scanned set is not empty"
[ "${#scanset[@]}" -gt 10 ] && pass || fail "only ${#scanset[@]} files"

# ERE -> "relpath:line:text" for every hit over the scanned set. grep exit 2
# (an error, not "no match") is reported as a hit, so the lint fails loudly.
scan() {
  local h="" rc=0
  LC_ALL=C grep -nHE -- "$1" "${scanset[@]}" > "$tmp/scan1"; rc=$?
  [ "$rc" -gt 1 ] && echo "SCAN-ERROR: grep exit $rc"
  while IFS= read -r h; do printf '%s\n' "${h#"$repo"/}"; done < "$tmp/scan1"
}

t "no emoji"
scan $'\xE2[\x98-\x9E]|\xE2[\xAC-\xAF]|\xF0\x9F|\xEF\xB8\x8F' > "$tmp/emoji"
[ -s "$tmp/emoji" ] && fail "$(head -5 "$tmp/emoji")" || pass

while IFS= read -r spec || [ -n "$spec" ]; do
  spec=${spec%$'\r'}
  case $spec in ''|'#'*) continue ;; esac
  re=${spec%%$'\t'*}
  allow=""; case $spec in *$'\t'*) allow=${spec#*$'\t'} ;; esac
  t "deleted term /$re/"
  scan "$re" > "$tmp/hits"
  if [ -n "$allow" ] && [ -s "$tmp/hits" ]; then
    # Drop hits whose own text (after file:line:) matches the allow-regex.
    while IFS= read -r h; do
      body=${h#*:}; body=${body#*:}
      printf '%s\n' "$body" | LC_ALL=C grep -qE -- "$allow" || printf '%s\n' "$h"
    done < "$tmp/hits" > "$tmp/hits2"
    mv "$tmp/hits2" "$tmp/hits"
  fi
  [ -s "$tmp/hits" ] && fail "$(head -5 "$tmp/hits")" || pass
done < "$repo/tests/lint/deleted-terms.txt"

t "reference citations exist"
scan '(\.\./\.\./)?reference/[a-z0-9-]+\.md' | LC_ALL=C grep -oE 'reference/[a-z0-9-]+\.md' | sort -u > "$tmp/cites"
missing=""
while IFS= read -r c; do [ -f "$repo/$c" ] || missing="$missing $c"; done < "$tmp/cites"
[ -z "$missing" ] && pass || fail "missing:$missing"

# --- kernel index, both ways ---------------------------------------------------
t "kernel index covers skills and reference files"
idx=$(tr -d '\r' < "$repo/hooks/kernel.md" | LC_ALL=C grep -E '^\*\*Index\.\*\*')
: > "$tmp/have"; : > "$tmp/listed"
for d in "$repo"/skills/*/; do d=${d%/}; printf 'skill:%s\n' "${d##*/}" >> "$tmp/have"; done
for r in "$repo"/reference/*.md; do printf 'ref:%s\n' "${r##*/}" >> "$tmp/have"; done
printf '%s\n' "$idx" | LC_ALL=C grep -oE '(^|[ (])/[a-z][a-z0-9-]*' | sed 's|^[ (]*/|skill:|' >> "$tmp/listed"
printf '%s\n' "$idx" | LC_ALL=C grep -oE '[a-z0-9-]+\.md' | sed 's|^|ref:|' >> "$tmp/listed"
sort -u "$tmp/have" -o "$tmp/have"; sort -u "$tmp/listed" -o "$tmp/listed"
nf=$(wc -l < "$tmp/have" | tr -d ' '); nl=$(wc -l < "$tmp/listed" | tr -d ' ')
echo "  index: files=$nf listed=$nl"
unlisted=$(comm -23 "$tmp/have" "$tmp/listed" | tr '\n' ' ')
phantom=$(comm -13 "$tmp/have" "$tmp/listed" | tr '\n' ' ')
if [ -n "$idx" ] && [ -z "$unlisted" ] && [ -z "$phantom" ] && [ "$nf" = "$nl" ]; then
  pass
else
  fail "not in the Index: ${unlisted:-none}; listed but missing: ${phantom:-none}"
fi

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
