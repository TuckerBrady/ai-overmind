#!/usr/bin/env bash
# Build overmind-mcp for every supported platform into mcp/dist/.
# Refreshes the embedded firmware copy first, then runs the tests.
set -euo pipefail
cd "$(dirname "$0")"

version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' ../.claude-plugin/plugin.json | head -1)
cp ../hooks/firmware.md firmware/firmware.md
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
