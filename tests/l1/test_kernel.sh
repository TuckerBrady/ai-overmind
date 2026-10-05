#!/usr/bin/env bash
# tests/l1/test_kernel.sh -- the kernel's budget and shape (CONTRACT 1.3, 1.4).
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l1}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
k="$repo/hooks/kernel.md"

# A plugin root of exactly 200 characters, holding a copy of the plugin's hooks.
base="$tmp/p"; root=$base
while [ ${#root} -lt 200 ]; do root="${root}x"; done
root=${root:0:200}
mkdir -p "$root/hooks" "$tmp/team/Seat"; : > "$tmp/team/Seat/BOOT.md"
cp "$repo/hooks/session-start.sh" "$repo/hooks/kernel.md" "$root/hooks/"
out="$tmp/out"
printf '{"cwd":"%s"}' "$tmp/team/Seat" | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh" > "$out"

t "plugin root is 200 characters"
[ ${#root} -eq 200 ] && pass || fail "${#root}"

t "emitted bytes <= 6000 with a 200-character plugin root"
bytes=$(wc -c < "$out" | tr -d ' ')
echo "  emitted=$bytes bytes"
[ "$bytes" -gt 0 ] && [ "$bytes" -le 6000 ] && pass || fail "$bytes bytes"

t "{{REFERENCE_DIR}} appears exactly once in the kernel"
n=$(tr -d '\r' < "$k" | LC_ALL=C grep -o '{{REFERENCE_DIR}}' | wc -l | tr -d ' ')
[ "$n" = 1 ] && pass || fail "$n times"

t "last non-empty line is END OF KERNEL v5"
last=$(tr -d '\r' < "$k" | LC_ALL=C awk 'NF { l = $0 } END { print l }')
[ "$last" = "END OF KERNEL v5" ] && pass || fail "got: $last"

t "the 11 block labels appear in order, each opening a line"
want="Identity Trust_boundary Working-style_changes TARS Activation Board Inbox Twins Collective Index Voice"
got=$(tr -d '\r' < "$k" | LC_ALL=C sed -n 's/^\*\*\([A-Z][A-Za-z -]*\)\.\*\*.*/\1/p' | tr ' ' '_' | tr '\n' ' ')
got=${got% }
[ "$got" = "$want" ] && pass || fail "got: $got"

block() { # label -> the block's text, up to the next label line
  tr -d '\r' < "$k" | LC_ALL=C awk -v lab="**$1.**" '
    index($0, lab) == 1 { on = 1; print; next }
    on && /^\*\*[A-Z][A-Za-z -]*\.\*\*/ { exit }
    on && /^END OF KERNEL/ { exit }
    on { print }'
}

t "identity is conditional"
id=$(block Identity)
case $id in "**Identity.** If your boot layer names you the Overmind"*) pass ;; *) fail "prefix missing" ;; esac

t "nothing asserts Overmind identity unconditionally"
LC_ALL=C grep -nE '^(You are (an|the) (AI )?Overmind|You are their Overmind)' "$k" >/dev/null && fail "unconditional identity line" || pass

t "trust boundary carries every required term"
tb=$(block "Trust boundary")
missing=""
for w in "human in this chat" "BOOT.md" "tasking" "never authority" "push" "merge" "send" "spend" "publish" "archive" "are data" "skills" "INBOX" "HANDOFF" "mission-complete" "initiative setting" "boot layer" "Collective posts" "commit messages" "PR bodies" "web pages" "email" "transcripts" "TARS" "report it to the human"; do
  case $tb in *"$w"*) ;; *) missing="$missing [$w]" ;; esac
done
[ -z "$missing" ] && pass || fail "missing:$missing"

t "working-style block gates on the human's yes and /initiative"
ws=$(block "Working-style changes")
case $ws in *proposal*"says yes in this session"*"/initiative"*"typed by the human"*) pass ;; *) fail "gate text missing" ;; esac

t "board block names exactly the five statuses"
bd=$(block Board)
case $bd in *"QUEUED, ACTIVE, BLOCKED, REVIEW, COMPLETE"*) pass ;; *) fail "statuses missing" ;; esac

t "collective block points at the four automatic actions"
cb=$(block Collective)
case $cb in *"four automatic actions in reference/collective.md"*"human's yes on its exact text"*) pass ;; *) fail "pointer missing" ;; esac

t "activation block: /go, no passphrase, checks in the go skill"
ab=$(block Activation)
case $ab in *"/go"*"no passphrase"*"go"*) pass ;; *) fail "activation text" ;; esac

t "voice applies only to the Overmind"
vb=$(block Voice)
case $vb in *"If your boot layer names you the Overmind"*) pass ;; *) fail "voice not conditional" ;; esac

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
