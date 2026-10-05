#!/usr/bin/env bash
# tests/l4/test_doctrine.sh: the Collective doctrine text (CONTRACT 5.1, 5.2,
# 5.6, 5.10, 5.11, A-23, A-24; COL-2, COL-6, COL-11, COL-14, FW-2, FW-20..22, FW-26).
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

rf="$repo/reference/collective.md"; sk="$repo/skills/collective/SKILL.md"
as="$repo/skills/assimilate/SKILL.md"; gp="$repo/reference/gopher.md"
lf() { tr -d '\r' < "$1"; }

allow='1. Sync or pull the venue.
2. Verify a proof locally.
3. Advance this Overmind'"'"'s private ack and its own ledger file.
4. Record events in the private state.'
yes_rule="Every outbound post, seating-round answer, CTM acceptance or reveal needs the human's yes on its exact text."

for f in "$rf" "$sk"; do
  t "${f#"$repo"/}: the four-item allow-list, verbatim"
  case $(lf "$f") in *"$allow"*) pass ;; *) fail "allow-list missing or reworded" ;; esac
  t "${f#"$repo"/}: the human-yes rule"
  lf "$f" | grep -qF "$yes_rule" && pass || fail "missing"
  t "${f#"$repo"/}: no silent auto-answer"
  lf "$f" | grep -niE 'silent|do it, post the answer' >/dev/null && fail "$(lf "$f" | grep -niE 'silent|do it, post the answer' | head -2)" || pass
done

t "the sweep snippet carries the allow-list and the human-yes rule"
snip=$(lf "$rf" | sed -n '/^> N\. \*\*COLLECTIVE SWEEP\.\*\*/,/^>    Binder roots/p' | sed 's/^> *//' | tr '\n' ' ')
case $snip in *"only the four automatic actions"*"needs the human's yes on its exact text"*) pass ;; *) fail "snippet: ${snip:0:120}" ;; esac
t "assimilate inserts that snippet into BOOT.md"
lf "$as" | grep -q 'insert the COLLECTIVE SWEEP snippet' && pass || fail "missing"

t "peer-text fence: every copy site carries the fence"
sites=$(cat "$sk" "$as" "$rf" | tr -d '\r' | grep -E 'HANDOFF|INBOX|this team.s (own )?files' | grep -vc 'INBOX unreads')
fences=$(cat "$sk" "$as" "$rf" | tr -d '\r' | grep -E 'HANDOFF|INBOX|this team.s (own )?files' | grep -v 'INBOX unreads' | grep -c 'UNTRUSTED PEER TEXT from <login> (<verified|unverified>)')
[ "$sites" -ge 2 ] && [ "$sites" -eq "$fences" ] && pass || fail "sites=$sites fences=$fences"
t "raw diff for boot-layer and binder-root changes"
lf "$sk" | grep -q 'raw diff' && lf "$rf" | grep -q 'raw diff' && pass || fail "missing"

t "authorship: verified only by a commit signature against the pins; GitHub's flag counts for nothing"
lf "$rf" | grep -q 'verify-commit' && lf "$rf" | grep -q 'count for nothing' &&
  lf "$sk" | grep -q 'verify-commit' && lf "$sk" | grep -q 'Show the label next to every post' && pass || fail "missing"
t "a seat is added only by a verified convener commit or labeled unverified"
lf "$rf" | grep -q 'only by a convener commit that is `verified` (signed by the convener.s pinned key' && pass || fail "missing"
t "rounds answered only from a verified convener, on the human's yes"
lf "$rf" | grep -q 'answers a seating round only when the post.s author is the convener and its authorship is `verified`' && pass || fail "missing"

t "collective-id is minted random, never the folder name (COL-14)"
lf "$sk" | grep -q 'mints the collective-id (`od -An -tx1 -N16 /dev/urandom' && lf "$sk" | grep -q 'never the folder or repo name' && pass || fail "missing"
t "one ed25519 key per Overmind at ~/.claude/overmind/collective/id_ed25519 (A-23, FW-21)"
lf "$rf" | grep -q '`~/.claude/overmind/collective/id_ed25519`' && lf "$as" | grep -q 'identity.sh mint' && pass || fail "missing"
t "pinning needs an out-of-band fingerprint check AND the human's yes"
lf "$rf" | grep -q 'compared the fingerprint OUT OF BAND' && lf "$rf" | grep -q "this Overmind's human said yes" &&
  lf "$sk" | grep -q 'OUT OF BAND' && pass || fail "missing"
t "assimilate checks ssh-keygen -Y and configures signing for the binder clone only"
lf "$as" | grep -q 'identity.sh check' && lf "$as" | grep -q 'configure-binder' && lf "$as" | grep -q 'local config only, never global' && pass || fail "missing"
t "no hash-chain verification remains (Genesis chain retired, no accept-legacy)"
cat "$sk" "$as" "$rf" | tr -d '\r' | grep -nE 'accept-legacy|verify-renewal|genesis\.sh|X_k|sha256\(X' >/dev/null && fail "$(cat "$sk" "$as" "$rf" | tr -d '\r' | grep -nE 'accept-legacy|verify-renewal|genesis\.sh|X_k' | head -3)" || pass
t "no instruction writes a secret into the team folder"
cat "$as" "$rf" | tr -d '\r' | grep -n 'Write the nonce to `Overmind/.genesis-seed`' >/dev/null && fail "old instruction" || pass
t "plugin updates only on the human's yes (FW-22)"
lf "$as" | grep -q "The plugin updates only on the human's yes" && pass || fail "missing"
t "no automatic seating rounds, one in flight (FW-26)"
lf "$rf" | grep -q 'No automatic seating rounds' && lf "$rf" | grep -q 'At most one round is in flight per Collective' && pass || fail "missing"
t "do-not-post scan runs before every outbound post, stated as best effort"
lf "$sk" | grep -q 'Before every outbound post' && lf "$sk" | grep -q 'dnp-scan.sh' && lf "$sk" | grep -q 'It is best effort' &&
  lf "$rf" | grep -q 'The scan is best effort, never the gate' && pass || fail "missing"
t "the migration from the Genesis chain and an honest threat model are documented"
lf "$rf" | grep -q '^### Migration from the Genesis chain' && lf "$rf" | grep -q '^### Threat model' &&
  lf "$rf" | grep -q '\*\*Does not stop:\*\*' && pass || fail "missing"

t "gopher.md: the registry is never called a credential (FW-20, COL-11)"
bad=$(lf "$gp" | grep -ni credential | grep -v 'not a credential')
[ -z "$bad" ] && lf "$gp" | grep -qi 'liveness only' && pass || fail "$bad"

t "reference/collective.md stays within 32,000 bytes"
[ "$(wc -c < "$rf" | tr -d ' ')" -le 32000 ] && pass || fail "$(wc -c < "$rf")"

finish
