#!/usr/bin/env bash
# Build overmind-mcp for every supported platform into mcp/dist/.
#
# First the copy step: refresh the embedded doctrine (firmware/kernel.md and
# firmware/reference/*.md) from ../hooks/kernel.md and ../reference/*.md,
# deleting any stale copy whose source is gone. Then the tests, then the
# binaries.
#
#   build.sh        copy, test, build
#   build.sh copy   the copy step only (run it after editing the kernel or a
#                   reference file, then commit the copies)
set -euo pipefail
cd "$(dirname "$0")"

copy_doctrine() {
  cp ../hooks/kernel.md firmware/kernel.md
  mkdir -p firmware/reference
  rm -f firmware/reference/*.md
  cp ../reference/*.md firmware/reference/
}

copy_doctrine
if [ "${1:-}" = copy ]; then
  exit 0
fi

version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' ../.claude-plugin/plugin.json | head -1)
go test ./... -count=1

rm -rf dist && mkdir -p dist
for target in windows/amd64 darwin/arm64 darwin/amd64 linux/amd64; do
  os=${target%/*}; arch=${target#*/}
  out="dist/overmind-mcp-${os}-${arch}"
  [ "$os" = windows ] && out="$out.exe"
  CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath \
    -ldflags "-s -w -X main.version=${version}" -o "$out" .
  echo "built $out ($(du -h "$out" | cut -f1))"
done
