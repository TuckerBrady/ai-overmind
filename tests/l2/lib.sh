#!/usr/bin/env bash
# tests/l2/lib.sh: helpers for the L2 (TARS) tests. Sourced by tests/l2/*.sh
# only; nothing outside this lane uses it.
#
# Provides: the t/pass/fail/finish counters, a temp dir removed on exit, the
# hook driver, PATH shims that log each external command, a fake gh, a team
# fixture and a transcript writer. Adversarial bytes are made at runtime.

set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${here%/tests/l2}
TARS=${TARS_UNDER_TEST:-$repo/hooks/tars.sh}
B=${BASH:-bash}
ok=0 no=0 name=""
t() { name=$1; }
pass() { ok=$(( ok + 1 )); }
fail() { no=$(( no + 1 )); echo "  FAIL: $name: $1"; }
# expect DESC COMMAND...: pass when the command succeeds.
expect() { local d=$1; shift; if "$@"; then pass; else fail "$d"; fi; }
finish() {
  if [ "$no" -eq 0 ]; then echo "PASS ${0##*/} ($ok cases)"; else echo "FAIL ${0##*/} ($no of $(( ok + no )))"; fi
  [ "$no" -eq 0 ]
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
TH="$tmp/tarshome"
SYSPATH=$PATH
cr=$'\r'

# jpath PATH: the path as a JSON string body (Windows form under Git Bash).
jpath() {
  local w=$1
  if command -v cygpath >/dev/null 2>&1; then w=$(cygpath -w "$1"); fi
  w=${w//\\/\\\\}
  printf '%s' "$w"
}

# hook SID CWD [TRANSCRIPT]: one UserPromptSubmit turn. Callers export the
# seams (TARS_NOW, TARS_COLLECTIVE_SYNC, ...) and HOOKPATH (the PATH to use).
hook() {
  local c tp=""
  c=$(jpath "$2")
  [ -n "${3:-}" ] && tp=$(jpath "$3")
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$1" "$tp" "$c" |
    PATH=${HOOKPATH:-$SYSPATH} TARS_HOME="$TH" "$B" "$TARS"
}

# mkshims DIR: a logging wrapper for each external tool tars.sh may call.
# Each call appends the tool name to $SHIMLOG, then runs the real tool.
mkshims() {
  local d=$1 tool real
  mkdir -p "$d"
  for tool in tail grep date mkdir find rm cksum timeout gtimeout sleep cat mv touch; do
    real=$(PATH=$SYSPATH command -v "$tool" 2>/dev/null) || continue
    case $real in /*) ;; *) continue ;; esac
    printf '#!/bin/sh\necho %s >> "$SHIMLOG"\nexec "%s" "$@"\n' "$tool" "$real" > "$d/$tool"
    chmod +x "$d/$tool"
  done
}

# mkgh DIR: a fake gh. It answers from files in $FAKEGH:
#   user_out, user_rc, user_err  for "gh api user"
#   commits, commits_rc          for "gh api repos/..." (new query)
#   commits_old                  when the query mentions the commit text field
# Every call's arguments are appended to $FAKEGH/calls.
mkgh() {
  local d=$1
  mkdir -p "$d"
  cat > "$d/gh" <<EOF
#!$B
f=\${FAKEGH:?}
printf '%s\n' "\$*" >> "\$f/calls"
show() { local l; [ -f "\$1" ] || return 0; while IFS= read -r l || [ -n "\$l" ]; do printf '%s\n' "\$l"; done < "\$1"; }
code() { local v=0; [ -f "\$1" ] && read -r v < "\$1"; return "\${v:-0}"; }
case "\$2" in
  user) show "\$f/user_out"; show "\$f/user_err" >&2; code "\$f/user_rc"; exit \$? ;;
  repos/*)
    case "\$*" in *message*) show "\$f/commits_old" ;; *) show "\$f/commits" ;; esac
    code "\$f/commits_rc"; exit \$? ;;
esac
exit 0
EOF
  chmod +x "$d/gh"
}

# mkteam ROOT [BINDER]: a team root with an Overmind seat and a Developer seat.
# With BINDER (owner/repo), the Overmind's BOOT.md lists it as a binder root.
mkteam() {
  local r=$1
  mkdir -p "$r/T-Bot - The Overmind" "$r/Nash - Developer"
  printf '# MISSION BOARD\n\n## Active\n\n| ID | Mission | Status | Priority |\n|----|---------|--------|----------|\n\n## Archive\n' > "$r/MISSION_BOARD.md"
  if [ -n "${2:-}" ]; then
    printf '# BOOT\n\nBinder roots (GitHub):\n   - `%s` - test venue\n' "$2" > "$r/T-Bot - The Overmind/BOOT.md"
  else
    printf '# BOOT\n' > "$r/T-Bot - The Overmind/BOOT.md"
  fi
  printf '# BOOT\n' > "$r/Nash - Developer/BOOT.md"
}

# old FILE...: set mtime to 2000-01-01, so anything written now is newer.
old() { touch -t 200001010000 "$@"; }

# backdate SID: make a session's last-turn marker old, so files written in the
# same second as that turn still count as new on the next one.
backdate() { [ -f "$TH/sessions/$1/marker" ] && old "$TH/sessions/$1/marker"; return 0; }

# txline FILE TOKENS [MODEL]: append one main-thread usage record.
txline() {
  printf '{"isSidechain":false,"type":"assistant","message":{"model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}\n' "${3:-claude-opus-4-1}" "$2" >> "$1"
}

# count PATTERN TEXT: lines of TEXT containing PATTERN (fixed string).
count() { local n=0 l; while IFS= read -r l; do case $l in *"$1"*) n=$(( n + 1 )) ;; esac; done <<< "$2"; printf '%s' "$n"; }

# grammar_ok TEXT: every line matches tests/l2/grammar.txt (CR stripped).
grammar_ok() {
  local g="$tmp/grammar.lf" l
  [ -f "$g" ] || {
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%"$cr"}
      case $l in ''|'#'*) continue ;; esac
      printf '%s\n' "$l"
    done < "$here/grammar.txt" > "$g"
  }
  # Callers join several turns' output, so blank lines between them are skipped.
  ! printf '%s\n' "$1" | LC_ALL=C grep -v '^$' | LC_ALL=C grep -Evxf "$g" >/dev/null
}
