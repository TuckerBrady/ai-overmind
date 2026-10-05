#!/usr/bin/env bash
# too-large.sh <transcript.jsonl> [--expect-kernel]
#
# /diagnostic B6: did the SessionStart hook's output reach the session whole?
#
# Claude Code saves a hook output over its size cap to disk and injects only a
# preview. The transcript then holds an attachment record whose fields read
#   "type":"attachment"  ...  "hookEvent":"SessionStart"
#   "content":"<persisted-output>\nOutput too large ..."
# The match is on those fields, written as real JSON keys (a quote that is not
# backslash-escaped). The same words quoted inside a message, a tool_use or a
# tool_result are escaped (\"hookEvent\":...) or sit in another field, and
# never count.
#
# Exit 1: a truncated SessionStart record exists.
# With --expect-kernel (use it when the session ran in a team folder), also
# exit 1 when no SessionStart record carries the kernel's header,
# "# AI OVERMIND KERNEL v5", as the start of its content or stdout.
# Exit 0 otherwise, including a missing transcript.
set -u
f=${1:-}
expect=""
[ "${2:-}" = "--expect-kernel" ] && expect=1
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "too-large: no transcript given or found; nothing to check" >&2
  exit 0
fi

LC_ALL=C awk -v expect="$expect" '
  function field(line, key, val,   re) {
    # "key":"val... as a real JSON key: the opening quote is not escaped.
    re = "(^|[^\\\\])\"" key "\"[ ]*:[ ]*\"" val
    return line ~ re
  }
  {
    if (!field($0, "type", "attachment")) next
    if (!field($0, "hookEvent", "SessionStart")) next
    if (field($0, "content", "<persisted-output>\\\\nOutput too large")) trunc++
    if (field($0, "content", "# AI OVERMIND KERNEL v5") || field($0, "stdout", "# AI OVERMIND KERNEL v5")) kern++
  }
  END {
    if (trunc > 0) { printf "too-large: %d SessionStart output(s) were truncated to a preview\n", trunc; exit 1 }
    if (expect != "" && kern == 0) { print "too-large: no SessionStart record carries the kernel header in this team-folder transcript"; exit 1 }
    exit 0
  }' "$f"
