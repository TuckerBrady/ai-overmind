#!/usr/bin/env bash
# session-start.sh -- the ai-overmind SessionStart hook (v5).
#
# Prints the kernel (hooks/kernel.md) into the session's context, and only
# in a team folder: the session's working directory, or its parent, holds a
# BOOT.md or a MISSION_BOARD.md. Anywhere else it prints nothing.
#
# Input: the hook JSON on stdin; only its "cwd" field is read. Empty stdin,
# malformed JSON or a missing kernel print nothing. Every path exits 0, so
# this hook can never block a session from starting.
#
# The kernel's single {{REFERENCE_DIR}} token becomes
# ${CLAUDE_PLUGIN_ROOT}/reference, with forward slashes.
#
# Portable to macOS /bin/bash 3.2: builtins only, no arrays, no jq.

main() {
  local input="" chunk="" cwd="" root="" kernel="" ref="" line="" pre="" post=""
  local tok='{{REFERENCE_DIR}}'

  while IFS= read -r chunk || [ -n "$chunk" ]; do
    input="$input$chunk"
  done

  # Trim surrounding whitespace, then require a JSON object.
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  case "$input" in
    '{'*'}') ;;
    *) return 0 ;;
  esac

  local re='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  if [[ "$input" =~ $re ]]; then
    cwd="${BASH_REMATCH[1]}"
  fi
  # No real directory path is longer than 4096 characters. A longer value is
  # treated as absent, so the unescape loop below stays bounded (a 32767-
  # character cwd once took 12 s here, past the hook's 10 s timeout).
  if [ "${#cwd}" -gt 4096 ]; then
    cwd=""
  fi
  # JSON unescape for a path: \" becomes ", \ (a Windows separator) and \/
  # become a forward slash. A stray single backslash is a separator too. A
  # value with no backslash needs no work.
  case "$cwd" in
    *"\\"*)
      local out="" c="" d="" i=0 n="${#cwd}"
      while [ "$i" -lt "$n" ]; do
        c="${cwd:$i:1}"
        if [ "$c" = "\\" ]; then
          d="${cwd:$((i + 1)):1}"
          case "$d" in
            '"') out="$out\""; i=$((i + 1)) ;;
            "\\" | /) out="$out/"; i=$((i + 1)) ;;
            *) out="$out/" ;;
          esac
        else
          out="$out$c"
        fi
        i=$((i + 1))
      done
      cwd="$out"
      ;;
  esac
  # A UNC path (//server/share/...) is never probed: on Windows a file test
  # against it opens an SMB connection to whatever host the JSON names, which
  # can stall past the hook's timeout and hands that host the user's NTLM
  # credentials. Team folders are local; a UNC cwd gets no kernel.
  case "$cwd" in
    //*) return 0 ;;
  esac
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    cwd="$PWD"
  fi
  case "$cwd" in
    //*) return 0 ;;
  esac
  while [ "${#cwd}" -gt 1 ] && [ "${cwd%/}" != "$cwd" ]; do
    cwd="${cwd%/}"
  done

  local parent="${cwd%/*}"
  [ -n "$parent" ] || parent="/"
  if ! { [ -f "$cwd/BOOT.md" ] || [ -f "$cwd/MISSION_BOARD.md" ] ||
         [ -f "$parent/BOOT.md" ] || [ -f "$parent/MISSION_BOARD.md" ]; }; then
    return 0
  fi

  root="${CLAUDE_PLUGIN_ROOT:-}"
  if [ -z "$root" ]; then
    case "${BASH_SOURCE[0]}" in
      */*) root="${BASH_SOURCE[0]%/*}/.." ;;
      *) root=".." ;;
    esac
  fi
  root="${root//\\//}"
  root="${root%/}"
  kernel="$root/hooks/kernel.md"
  [ -f "$kernel" ] || return 0
  ref="$root/reference"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      *"$tok"*)
        pre="${line%%"$tok"*}"
        post="${line#*"$tok"}"
        line="$pre$ref$post"
        ;;
    esac
    printf '%s\n' "$line"
  done < "$kernel"
  return 0
}

main 2>/dev/null
exit 0
