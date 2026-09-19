#!/usr/bin/env bash
# TARS — the turn hook for ai-overmind (UserPromptSubmit).
#
# Named for the robot in Interstellar, honesty setting 100%. TARS reports
# facts and only facts: what changed on disk or in a Collective since the last
# message. The Overmind decides what those facts mean and what to do about them.
#
# Rules this script lives by:
#   - Fast: bash builtins only on the common path, so a quiet message launches
#     no extra processes. Anything on the network runs in the background and is
#     reported on the NEXT message.
#   - Quiet: prints nothing unless something changed or a checkpoint is due.
#   - Never blocks: every path exits 0. (Exit 2 on UserPromptSubmit would erase
#     the human's prompt.)
#
# Line types:
#   "TARS: ..."        a fact for the human. The Overmind relays it verbatim.
#   "TARS (cue): ..."  a prompt for the Overmind to act. Not relayed; only what
#                      the Overmind finds gets reported.
#
# State lives in ${TARS_HOME:-$HOME/.claude/tars}. Nothing is written into the
# team folders.

set +e
export LC_ALL=C

IFS= read -r -d '' input
input=${input//$'\n'/ }
input=${input//$'\r'/ }

field() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ $input =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}

sid=$(field session_id); sid=${sid//[^A-Za-z0-9_-]/}; sid=${sid:0:40}
[ -n "$sid" ] || sid=nosession
cwd=$(field cwd); cwd=${cwd//\\\\//}
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$PWD
cwd=${cwd%/}

home=${TARS_HOME:-$HOME/.claude/tars}
st="$home/sessions/$sid"
[ -d "$st" ] || mkdir -p "$st" "$home/collective" 2>/dev/null || exit 0

now=${EPOCHSECONDS:-$(date +%s)}
out=""
say() { out+="TARS: $1"$'\n'; }
cue() { out+="TARS (cue): $1"$'\n'; }
getn() { local v=""; [ -f "$1" ] && read -r v < "$1"; case $v in ''|*[!0-9]*) v=0 ;; esac; printf '%s' "$v"; }
put() { printf '%s' "$2" > "$1"; }

# fresh FILE REF: FILE was written since REF, not just stamped. /go writes an
# "ACTIVATED:" line into a handoff when it runs it, which also bumps the
# file's mtime. A stamped file is a brief that was read, not a new one.
# A newly written handoff or brief overwrites the file, so it has no stamp.
fresh() {
  local line n=0
  [ "$1" -nt "$2" ] || return 1
  while (( n++ < 40 )) && IFS= read -r line; do
    [[ $line =~ ^[[:space:]*_]*ACTIVATED: ]] && return 1
  done < "$1"
  return 0
}

# written_here FILE: this session wrote FILE, even if another session has
# since run /go on it and stamped it ACTIVATED. Unstamped and newer than the
# session start counts. A stamped file counts only when its WRITTEN: header is
# at or after this session's start minute (string compare, no date calls).
written_here() {
  local line n=0 since="" w re='WRITTEN:[^0-9]*([0-9]{4}-[0-9]{2}-[0-9]{2})[ T]([0-9]{2}:[0-9]{2})'
  [ "$1" -nt "$st/started" ] || return 1
  fresh "$1" "$st/started" && return 0
  [ -f "$st/started_at" ] && read -r since < "$st/started_at"
  [ -n "$since" ] || return 1
  while (( n++ < 40 )) && IFS= read -r line; do
    if [[ $line =~ $re ]]; then
      w="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      [[ $w < $since ]] && return 1
      return 0
    fi
  done < "$1"
  return 1
}

first=""
if [ ! -f "$st/started" ]; then
  first=1
  : > "$st/started"
  printf '%(%Y-%m-%d %H:%M)T' -1 > "$st/started_at" 2>/dev/null
  : > "$st/marker"
  : > "$st/bootref"
  put "$st/lastwatch" "$now"
  find "$home/sessions" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
fi

# ---------------------------------------------------------------- checkpoints
turns=$(( $(getn "$st/turns") + 1 ))
put "$st/turns" "$turns"

# Quiet until the soft threshold, then every 5th turn. A session this short
# doesn't need a handoff, so an early checkpoint is noise. Tune per install with
# TARS_SOFT / TARS_HARD (the "env" block of settings.json reaches hooks).
soft=${TARS_SOFT:-20}; case $soft in ''|*[!0-9]*) soft=20 ;; esac
hard=${TARS_HARD:-45}; case $hard in ''|*[!0-9]*) hard=45 ;; esac
(( hard > soft )) || hard=$(( soft + 25 ))

if (( turns >= soft && ( (turns - soft) % 5 == 0 || turns == hard ) )); then
  handoff="No handoff written this session."
  for h in "$cwd/HANDOFF.md" "$cwd/.auto-memory/HANDOFF.md"; do
    written_here "$h" && { handoff="Handoff written this session."; break; }
  done
  if (( turns >= hard )); then say "turn $turns. $handoff Hard threshold ($hard) reached."
  else say "turn $turns. $handoff Soft threshold ($soft) reached. Handoff suggested."
  fi
fi

# ---------------------------------------------------------------- boot layer
# Pinned config: this session booted on the BOOT.md that existed when it
# started. An edit since then (the Overmind propagating a change) means it is
# running a superseded boot layer until it re-reads the file. Reported once
# per edit; the reference moves forward each time.
if [ -z "$first" ] && [ -f "$cwd/BOOT.md" ] && [ -f "$st/bootref" ] && [ "$cwd/BOOT.md" -nt "$st/bootref" ]; then
  say "BOOT.md changed since this session booted. Re-read it before your next action."
  : > "$st/bootref"
fi

# ---------------------------------------------------------------- which seat
root=""
parent=${cwd%/*}
if [ -f "$cwd/MISSION_BOARD.md" ]; then root=$cwd
elif [ -f "$parent/MISSION_BOARD.md" ]; then root=$parent
fi

seat=specialist
base=${cwd##*/}
[[ ${base,,} == *overmind* ]] && seat=overmind
[ -n "$root" ] && [ "$root" = "$cwd" ] && seat=overmind

overmind_dir=$cwd
if [ "$seat" = overmind ] && [ "$root" = "$cwd" ]; then
  shopt -s nocaseglob nullglob
  for d in "$root"/*overmind*/; do overmind_dir=${d%/}; break; done
  shopt -u nocaseglob nullglob
fi

# Unread inbox entries: recount only when the inbox changed; report growth.
inbox_growth() {
  local f="$1/INBOX.md" cur=0 prev line
  [ -f "$f" ] || return
  [ -z "$first" ] && [ ! "$f" -nt "$st/marker" ] && return
  while IFS= read -r line || [ -n "$line" ]; do [[ $line == *UNREAD* ]] && ((cur++)); done < "$f"
  prev=$(getn "$st/unread")
  put "$st/unread" "$cur"
  [ -n "$first" ] && return
  (( cur > prev )) && say "$cur unread inbox entries (was $prev)."
}

# ---------------------------------------------------------------- missions
if [ -n "$root" ]; then
  if [ "$seat" = overmind ]; then
    shopt -s nullglob
    for f in "$root"/*/mission-complete.md; do
      [ "$f" -nt "$st/marker" ] || continue
      d=${f%/mission-complete.md}; who=${d##*/}; mid=""
      while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ([A-Z]{2,5}-[0-9]{2,4}[a-z]?) ]]; then mid=${BASH_REMATCH[1]}; break; fi
      done < "$f"
      say "$who wrote mission-complete.md${mid:+ for $mid}."
    done
    shopt -u nullglob

    inbox_growth "$overmind_dir"

    board="$root/MISSION_BOARD.md"
    if [ -f "$board" ]; then
      # Re-scan the board only when it changed since the last scan.
      if [ ! -f "$st/boardscan" ] || [ "$board" -nt "$st/boardscan" ]; then
        count=0; tier=""
        while IFS= read -r line || [ -n "$line" ]; do
          [[ $line == \|* ]] || continue
          [[ $line =~ ACTIVE|PENDING|QUEUED|BLOCKED|REVIEW ]] || continue
          ((count++))
          if [[ $line == *CRITICAL* ]]; then tier=CRITICAL
          elif [[ $line == *STANDARD* && $tier != CRITICAL ]]; then tier=STANDARD
          elif [ -z "$tier" ]; then tier=LOW
          fi
        done < "$board"
        put "$st/boardscan" "$count $tier"
      fi
      read -r count tier < "$st/boardscan"
      if (( ${count:-0} > 0 )); then
        case $tier in CRITICAL) cadence=60 ;; STANDARD) cadence=300 ;; *) cadence=3600 ;; esac
        last=$(getn "$st/lastwatch")
        if [ -z "$first" ] && (( now - last >= cadence )); then
          cue "mission watch due: $count in flight, highest priority $tier. Run the watch rules and report only what you find."
          put "$st/lastwatch" "$now"
        fi
      fi
    fi
  else
    fresh "$cwd/HANDOFF.md" "$st/marker" && say "a new brief was written to your HANDOFF.md."
    inbox_growth "$cwd"
  fi
fi

# ---------------------------------------------------------------- working style
# The team-wide WORKING_WITH_[name].md changed: every seat hears it, so a
# session that booted on the old initiative setting knows to re-read it.
if [ -n "$root" ] && [ -z "$first" ]; then
  shopt -s nullglob
  for f in "$root"/WORKING_WITH_*.md; do
    [ "$f" -nt "$st/marker" ] || continue
    pct="" n=0
    while (( n++ < 40 )) && IFS= read -r line; do
      [[ $line =~ ^#+[[:space:]]*Initiative\ setting:[[:space:]]*([0-9]{1,3})% ]] && { pct=${BASH_REMATCH[1]}; break; }
    done < "$f"
    say "${f##*/} was updated${pct:+ (initiative setting $pct%)}. Re-read it before your next action."
  done
  shopt -u nullglob
fi

# ---------------------------------------------------------------- collective
if [ "$seat" = overmind ] && [ -f "$overmind_dir/BOOT.md" ]; then
  # Report what the last background check found.
  if [ -s "$st/collective.pending" ]; then
    while IFS= read -r line; do [ -n "$line" ] && say "$line"; done < "$st/collective.pending"
    : > "$st/collective.pending"
  fi

  lastc=$(getn "$st/lastcollective")
  if (( now - lastc >= 300 )); then
    put "$st/lastcollective" "$now"
    (
      command -v gh >/dev/null 2>&1 || exit 0
      repos=$(awk '/Binder roots/{f=1} f{print; if (++n > 12) exit}' "$overmind_dir/BOOT.md" 2>/dev/null |
        grep -oE '`(github:)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+`' | tr -d '`' | sed 's/^github://' |
        grep -v '\.md$' | sort -u)
      [ -n "$repos" ] || exit 0
      me=""; [ -f "$home/gh_login" ] && read -r me < "$home/gh_login"
      if [ -z "$me" ]; then
        me=$(timeout 8 gh api user --jq .login 2>/dev/null)
        [ -n "$me" ] && printf '%s' "$me" > "$home/gh_login"
      fi
      for r in $repos; do
        seen="$home/collective/seen_${r//\//_}"
        lines=$(timeout 8 gh api "repos/$r/commits?per_page=15" \
          --jq '.[] | "\(.sha) \(.author.login // (.commit.author.name | gsub(" "; "_"))) \(.commit.message | split("\n")[0])"' 2>/dev/null) || continue
        [ -n "$lines" ] || continue
        if [ ! -f "$seen" ]; then
          printf '%s\n' "$lines" | cut -d' ' -f1 > "$seen"
          continue
        fi
        # Oldest first, so reports read in the order things happened.
        mapfile -t rows <<< "$lines"
        for (( i=${#rows[@]}-1; i>=0; i-- )); do
          read -r sha author msg <<< "${rows[i]}"
          [ -n "$sha" ] || continue
          grep -qx "$sha" "$seen" 2>/dev/null && continue
          printf '%s\n' "$sha" >> "$seen"
          [ -n "$me" ] && [ "$author" = "$me" ] && continue
          printf '%s pushed to %s: %s\n' "$author" "$r" "${msg:0:120}" >> "$st/collective.pending"
        done
      done
    ) </dev/null >/dev/null 2>&1 &
  fi
fi

: > "$st/marker"
[ -n "$out" ] && printf '%s' "$out"
exit 0
