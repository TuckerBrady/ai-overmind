#!/usr/bin/env bash
# tests/run-all.sh -- run every lane test (tests/*/test_*.sh) and every lint
# (tests/lint/*.sh) with the invoking bash, print PASS or FAIL per file, and
# exit non-zero if any file fails. Run it as `bash tests/run-all.sh`, or as
# `/bin/bash tests/run-all.sh` on macOS to test under bash 3.2.
set -u
here=$(cd "$(dirname "$0")" && pwd)
sh_bin=${BASH:-bash}
pass=0; failn=0; failed=""
for f in "$here"/*/test_*.sh "$here"/lint/*.sh; do
  [ -f "$f" ] || continue
  rel=${f#"$here"/}
  log=$("$sh_bin" "$f" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    pass=$((pass+1)); echo "PASS $rel"
  else
    failn=$((failn+1)); failed="$failed $rel"; echo "FAIL $rel (exit $rc)"
    printf '%s\n' "$log" | sed 's/^/    /' | tail -40
  fi
done
echo "run-all: $pass passed, $failn failed ($BASH_VERSION)"
[ $failn -eq 0 ]
