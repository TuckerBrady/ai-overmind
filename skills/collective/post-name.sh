#!/usr/bin/env bash
# skills/collective/post-name.sh: name a new post (CONTRACT 5.9, COL-12).
#
#   post-name.sh <posts-dir> <author> <PERF> <slug>
#
# Prints YYYYMMDD-HHMM-<author>--<PERF>-<slug>.md, where the stamp is the later
# of this machine's clock and the newest non-future post in <posts-dir> plus
# one minute. A post named more than 10 minutes ahead of this clock is
# flagged on stderr and ignored for naming, so one bad clock cannot drag every
# later name forward. Names are display order only; nothing reads them as
# delivery order. Exit: 0 ok, 2 usage.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

[ $# -eq 4 ] || die 2 "usage: post-name.sh <posts-dir> <author> <PERF> <slug>"
dir=$1 author=$2 perf=$3 slug=$4
case $author in ''|*[!a-z0-9-]*) die 2 "author must be lowercase letters, digits and -" ;; esac
case $slug in ''|*[!a-z0-9-]*) die 2 "slug must be lowercase letters, digits and -" ;; esac
case $perf in TASK|STAT|ASK|ANS|INFO|DEC|ACK|REPLY) ;; *) die 2 "PERF must be TASK STAT ASK ANS INFO DEC ACK or REPLY" ;; esac
[ -d "$dir" ] || die 2 "no such directory: $dir"

now=$(stamp_min "$(now_stamp)")
best=$now
for f in "$dir"/*.md; do
  [ -e "$f" ] || continue
  s=$(post_stamp "$f") || continue
  m=$(stamp_min "$s")
  if [ "$m" -gt $(( now + 10 )) ]; then
    printf 'FUTURE %s: named more than 10 minutes ahead of this clock; ignored for naming\n' "${f##*/}" >&2
    continue
  fi
  [ $(( m + 1 )) -gt "$best" ] && best=$(( m + 1 ))
done
st=$(min_stamp "$best")
printf '%s-%s-%s--%s-%s.md\n' "${st:0:8}" "${st:8:4}" "$author" "$perf" "$slug"
