#!/usr/bin/env bash
# fwhash.sh <plugin-root>
#
# Prints the 64-hex firmware hash of an installed plugin (CONTRACT 7.5): for
# hooks/kernel.md, then each reference/*.md in byte order of relative path,
# append "=== <relpath>\n" and the file's text with CRLF turned into LF and a
# final LF added when missing; the hash is the lowercase sha256 of the result.
# overmind-mcp prints the first 12 hex of the same value on its Engine line.
set -u
root=${1:-}
root=${root%/}
if [ -z "$root" ] || [ ! -f "$root/hooks/kernel.md" ]; then
  echo "fwhash: usage: fwhash.sh <plugin-root> (no hooks/kernel.md there)" >&2
  exit 2
fi

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256
  else openssl dgst -sha256 -r
  fi
}

emit() { # relpath file
  printf '=== %s\n' "$1"
  # CRLF -> LF; awk prints every line with a final LF, adding one if missing.
  LC_ALL=C awk '{ sub(/\r$/, ""); print }' "$2"
}

{
  emit hooks/kernel.md "$root/hooks/kernel.md"
  for f in $(cd "$root" && LC_ALL=C ls reference/*.md 2>/dev/null | LC_ALL=C sort); do
    emit "$f" "$root/$f"
  done
} | sha | LC_ALL=C sed 's/[^0-9a-f].*//' | tr -d '\n'
echo
