#!/usr/bin/env bash
# tests/l4/test_dnp.sh: the do-not-post scan (CONTRACT 5.7, COL-7, GAP-36).
# At least two positive and two clean cases per category. Every positive
# exits 1 and names its category; every clean case exits 0. Key-shaped
# values are assembled at runtime (rep) so no committed file holds one.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

rep() { local i=0 o=""; while [ "$i" -lt "$2" ]; do o="$o$1"; i=$(( i + 1 )); done; printf '%s' "$o"; }

hit() { # CATEGORY TEXT
  local out rc
  out=$(printf '%s\n' "$2" | "$B" "$DNP"); rc=$?
  t "$1 positive: ${2:0:50}"
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^DNP $1 "; then pass; else fail "rc=$rc out=$out"; fi
  case $out in *"$2"*) fail "the scan echoed the matched text" ;; esac
}
clean() { # CATEGORY TEXT
  local out rc
  out=$(printf '%s\n' "$2" | "$B" "$DNP"); rc=$?
  t "$1 clean: ${2:0:50}"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && pass || fail "rc=$rc out=$out"
}

hit PAY "Her salary is going up next quarter."
hit PAY "Bonus came in at \$12,500 this year."
hit PAY "Offer was \$185k per year plus equity."
clean PAY "Pay attention to the payload size in each post."
clean PAY "We raised the bar on test coverage and the bonus round is fun."

hit HEALTH "Started a new medication last week."
hit HEALTH "Dose is 50 mg twice a day."
hit HEALTH "Coded as F32.9 on the chart."
clean HEALTH "Run /diagnostic before the release."
clean HEALTH "Health check returned 200 in 12 ms; version v10.1.0 shipped."

hit FAMILY-PII "DOB: 04/12/2015 on the form."
hit FAMILY-PII "Mail it to 1234 Maple Grove Drive please."
hit FAMILY-PII "Call me at (555) 867-5309 tonight."
hit FAMILY-PII "My daughter starts at the new elementary school Monday."
clean FAMILY-PII "The child process exits with status 0."
clean FAMILY-PII "Released on 2026-10-05 with 4 fixes in 3 files."
clean FAMILY-PII "A school of fish is a nice metaphor for a swarm."

hit CREDENTIAL "password: $(rep z 10)"
hit CREDENTIAL "api_key = $(rep x 24)"
hit CREDENTIAL "token ghp_$(rep A 36) leaked"
hit CREDENTIAL "-----BEGIN OPENSSH PRIVATE KEY-----"
clean CREDENTIAL "Rotate the API key in the dashboard when asked."
clean CREDENTIAL "The token budget for the kernel is 6000 bytes."

hit FINANCIAL-ACCOUNT "Routing number: $(rep 1 9)"
hit FINANCIAL-ACCOUNT "Card 4111 1111 1111 1111 expires soon."
hit FINANCIAL-ACCOUNT "Acct # $(rep 7 10) at the credit union."
clean FINANCIAL-ACCOUNT "The account page lists 3 seats."
clean FINANCIAL-ACCOUNT "Commit d3f4f96 merged PR #30 at 20261005-1512."

hit GOV-ID "SSN 078-05-1120 on file."
hit GOV-ID "Passport no: X$(rep 1 8)"
hit GOV-ID "Driver's license number: D$(rep 2 7)"
clean GOV-ID "Passport photos are due Friday."
clean GOV-ID "Ticket 123-4567 closed; build 2026-10-05 is green."

t "every category is named in a multi-hit post, each once"
out=$(printf 'salary talk\nmedication list\nDOB: 1/2/2010\npassword: %s\nrouting: %s\nSSN 078-05-1120\n' "$(rep z 6)" "$(rep 3 9)" | "$B" "$DNP"); rc=$?
n=$(printf '%s\n' "$out" | grep -c '^DNP ')
[ "$rc" -eq 1 ] && [ "$n" -eq 6 ] && pass || fail "rc=$rc n=$n out=$out"

t "an empty post is clean"
out=$(printf '' | "$B" "$DNP"); rc=$?
[ "$rc" -eq 0 ] && pass || fail "rc=$rc"

t "no literal person names in the scanner (GAP-36): only pattern classes"
# Every alternation word in the script is a class word; spot-check that no
# capitalized given-name-plus-surname pair appears outside comments.
if grep -v '^[[:space:]]*#' "$DNP" | grep -En '[A-Z][a-z]+ [A-Z][a-z]+' | grep -v 'DNP\|usage' >/dev/null; then
  fail "$(grep -v '^[[:space:]]*#' "$DNP" | grep -En '[A-Z][a-z]+ [A-Z][a-z]+' | head -3)"
else
  pass
fi

finish
