#!/usr/bin/env bash
# too-large.sh <transcript.jsonl>
#
# /diagnostic B6: did the SessionStart hook's output reach the session whole?
# Claude Code saves a hook output over its size cap to disk and injects only a
# preview, recording "Output too large" in the SessionStart attachment. Exit 1
# when any transcript line carries "Output too large" and "SessionStart" but is
# not a tool_use or tool_result record (a tool call that merely quotes the
# phrase is not a truncated hook). Exit 0 otherwise, including a missing file.
set -u
f=${1:-}
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "too-large: no transcript given or found; nothing to check" >&2
  exit 0
fi
hits=$(LC_ALL=C grep -F 'Output too large' -- "$f" | LC_ALL=C grep -F 'SessionStart' |
  LC_ALL=C grep -vF '"tool_use"' | LC_ALL=C grep -vF '"tool_result"' | wc -l | tr -d ' ')
if [ "${hits:-0}" -gt 0 ]; then
  echo "too-large: $hits SessionStart output(s) were truncated to a preview in $f"
  exit 1
fi
exit 0
