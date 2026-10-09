#!/usr/bin/env bash
# skills/assimilate/identity.sh: this Overmind's Collective signing key
# (CONTRACT A-23). One ed25519 key per Overmind, used for Proof A and for
# signing commits in binder clones. The private key never leaves
# ~/.claude/overmind/collective/id_ed25519.
#
#   identity.sh check                 can this runtime sign and verify? (ssh-keygen -Y)
#   identity.sh mint                  create the key if there is none
#   identity.sh show                  print the public key line and its fingerprint
#   identity.sh configure-binder <clone>
#                                     sign every commit in that clone with the key
#                                     (local config only, never global)
#   identity.sh publish-github        add the PUBLIC key to the signed-in gh account
#                                     as an SSH signing key, so peers can pin it
#                                     with state.sh pin-github (idempotent)
#
# Exit: 0 ok, 1 refused, 2 usage, 3 missing state, 4 missing capability.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../collective/lib.sh"
umask 077

usage() { die 2 "usage: identity.sh check | mint | show | configure-binder <clone> | publish-github"; }

cmd=${1:-}
[ $# -ge 1 ] && shift
k=$(key_file)

case $cmd in
  check)
    [ $# -eq 0 ] || usage
    if have_sshsig; then
      echo "ok: ssh-keygen signs and verifies ($(ssh -V 2>&1 | head -1))"
    else
      echo "UNAVAILABLE: ssh-keygen -Y sign/verify does not work here (needs OpenSSH 8.1 or later)."
      echo "Seats from this runtime stay PROVISIONAL and nothing is verified automatically."
      exit 4
    fi
    ;;

  mint)
    [ $# -eq 0 ] || usage
    if [ -f "$k" ]; then
      [ -f "$k.pub" ] && pubkey_ok "$k.pub" || die 1 "a key exists at $k but its public half is missing or not ed25519; fix by hand, never overwrite"
      echo "already minted: $(fingerprint "$k.pub")"
      exit 0
    fi
    have_sshsig || die 4 "ssh-keygen -Y sign/verify is not available; cannot mint"
    mkdir -p "$(coll_dir)" || die 3 "cannot create $(coll_dir)"
    ssh-keygen -q -t ed25519 -N "" -C "ai-overmind-collective" -f "$k" </dev/null >/dev/null 2>&1 ||
      die 3 "ssh-keygen could not write $k"
    chmod 600 "$k" 2>/dev/null
    echo "minted: $(fingerprint "$k.pub")"
    ;;

  show)
    [ $# -eq 0 ] || usage
    [ -f "$k.pub" ] || die 3 "no key: run identity.sh mint"
    printf 'key: %s\nfingerprint: %s\n' "$(key_body "$k.pub")" "$(fingerprint "$k.pub")"
    ;;

  configure-binder)
    [ $# -eq 1 ] || usage
    [ -f "$k" ] || die 3 "no key: run identity.sh mint"
    git -C "$1" rev-parse --git-dir >/dev/null 2>&1 || die 2 "not a git clone: $1"
    git -C "$1" config --local gpg.format ssh &&
      git -C "$1" config --local user.signingkey "$k" &&
      git -C "$1" config --local commit.gpgsign true || die 3 "could not write the clone's local config"
    echo "this clone now signs every commit with $(fingerprint "$k.pub")"
    ;;

  publish-github)
    # Only the .pub is ever read or sent. The private key is not touched.
    [ $# -eq 0 ] || usage
    pub="$k.pub"
    [ -f "$pub" ] || die 3 "no key: run identity.sh mint"
    pubkey_ok "$pub" || die 1 "the public key at $pub is not a single ssh-ed25519 key; fix by hand"
    command -v gh >/dev/null 2>&1 ||
      die 4 "gh (GitHub CLI) is not installed. Install it from https://cli.github.com, sign in, then run this one-time fix: $GH_SCOPE_FIX"
    gt=$(mktemp -d "${TMPDIR:-/tmp}/ovmgh.XXXXXX") || die 3 "cannot make a temp dir"
    if ! bounded 30 "$gt/keys" "$gt/err" gh api --hostname github.com -H 'Accept: application/vnd.github+json' \
         "user/ssh_signing_keys?per_page=$GH_MAX_KEYS"; then
      rm -rf "$gt"
      die 4 "gh cannot read this account's SSH signing keys (the token lacks the scope, or gh is not signed in). One-time fix: $GH_SCOPE_FIX"
    fi
    if ! gh_key_bodies "$gt/keys" > "$gt/bodies"; then
      rm -rf "$gt"; die 3 "GitHub's answer is not a key list; nothing published"
    fi
    mine=$(key_body "$pub"); fpr=$(fingerprint "$pub")
    while IFS= read -r kb; do
      [ "$kb" = "$mine" ] && { rm -rf "$gt"; echo "already published: $fpr"; exit 0; }
    done < "$gt/bodies"
    host=$(uname -n 2>/dev/null | LC_ALL=C tr -cd 'A-Za-z0-9._-' | cut -c1-60)
    if ! bounded 30 "$gt/out" "$gt/err" gh ssh-key add "$pub" --type signing --title "ai-overmind collective (${host:-unknown})"; then
      if LC_ALL=C grep -qiE 'scope|HTTP 40[34]|admin:ssh_signing_key' "$gt/err"; then
        rm -rf "$gt"; die 4 "gh's token lacks the scope to add a signing key. One-time fix: $GH_SCOPE_FIX"
      fi
      msg=$(LC_ALL=C tr -d '\000-\011\013-\037\177' < "$gt/err" | head -3)
      rm -rf "$gt"; die 1 "gh could not add the signing key: $msg"
    fi
    login=""
    if bounded 30 "$gt/user" "$gt/err" gh api --hostname github.com user; then
      login=$(tr -d '\r\n' < "$gt/user" | LC_ALL=C grep -oE '"login"[ ]*:[ ]*"[A-Za-z0-9-]+"' | head -1 | sed 's/.*"\([A-Za-z0-9-]*\)"$/\1/')
    fi
    rm -rf "$gt"
    echo "published: $fpr as an SSH signing key${login:+ on GitHub account $login}"
    ;;

  *) usage ;;
esac
