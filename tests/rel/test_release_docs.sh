#!/usr/bin/env bash
# tests/rel/test_release_docs.sh -- the OPS-030 release-lane doc and CI items:
# A-33 S-4 (alloc prefix wording), A-29 (claims keyed by the CLI session id),
# A-30 (TARS read caps documented), the team-root rule in reference/tars.md,
# A-16 (verbose go test on ubuntu), and the GAP-1 copies of every edited file.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
g() { tr -d '\r' < "$repo/$1"; }

t "A-33 S-4: reference/dispatch.md states the alloc prefix as alloc-id.sh enforces it"
d=$(g reference/dispatch.md)
case $d in
  *'two to five capitals'*) fail "stale wording still present" ;;
  *'team prefix of a capital letter, then up to four more capitals or digits'*)
    grep -q '\^\[A-Z\]\[A-Z0-9\]{0,4}\$' "$repo/skills/dispatch/alloc-id.sh" && pass || fail "alloc-id.sh rule changed" ;;
  *) fail "new wording missing" ;;
esac

t "A-29: reference/tars.md and reference/activation.md key claims by the CLI session id"
bad=""
for f in reference/tars.md reference/activation.md; do
  x=$(g "$f")
  case $x in *'CLI session id'*'${CLAUDE_SESSION_ID}'*'local_'*) ;; *) bad="$bad $f" ;; esac
done
[ -z "$bad" ] && pass || fail "missing in:$bad"

t "A-30: reference/tars.md documents the 512 KiB and 2,048-line caps"
x=$(g reference/tars.md)
case $x in *'512 KiB'*'2,048 candidate lines'*) pass ;; *) fail "caps not documented" ;; esac

t "reference/tars.md states the nearest-live-board team root and the retired copy"
case $x in *'nearest of that directory and its two parents that holds a live `MISSION_BOARD.md`'*'RETIRED BRIDGE COPY'*) pass ;; *) fail "team-root rule not stated" ;; esac

t "A-16: the ubuntu CI job runs go test -v"
c=$(g .github/workflows/ci.yml | sed -n '/^  ubuntu:/,/^  macos:/p')
case $c in *'go test -v ./... -count=1'*) pass ;; *) fail "no -v on the ubuntu go test step" ;; esac

t "GAP-1: the mcp/firmware copies of the edited reference files match their sources"
bad=""
for f in tars.md activation.md dispatch.md twins.md; do
  cmp -s <(g "reference/$f") <(g "mcp/firmware/reference/$f") || bad="$bad $f"
done
[ -z "$bad" ] && pass || fail "stale copies:$bad"

finish
