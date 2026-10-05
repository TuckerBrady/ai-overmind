#!/usr/bin/env bash
# GAP-9: run-all runs tests/*/test_*.sh, so this wrapper puts the fuzz
# harness (with its positive control) in every run, at the fixed seed and N.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$(FUZZ_SEED=20261004 FUZZ_N=200 "${BASH:-bash}" "$here/fuzz_tars.sh"); rc=$?
printf '%s\n' "$out" | tail -n 3
if [ "$rc" -eq 0 ]; then echo "PASS ${0##*/} (1 cases)"; else echo "FAIL ${0##*/} (1 of 1)"; fi
exit "$rc"
