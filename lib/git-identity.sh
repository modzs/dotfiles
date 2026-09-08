#!/usr/bin/env bash
# lib/git-identity.sh - the single definition of "what identity does git report
# on this machine, and where does it come from".
#
# Sourced by bootstrap.sh and rebuild.sh, which ask the same question at two
# different moments: bootstrap.sh once, right after the first switch, and
# rebuild.sh after every later one. The answer is only final after the switch,
# because the switch is what installs home.nix's `programs.git.includes` entry
# for ~/.gitconfig.local. Keeping the logic here means the two callers cannot
# drift apart, for the same reason lib/dotfiles-link.sh exists.
#
# What this must never do, each rule paid for once already:
#   - state or imply a rule about how git ranks config files. It reports the
#     value and the file git itself named, and stops there;
#   - compose a `name <email>` line out of partial data. An empty half inside a
#     full identity line reads as a whole identity that happens to look odd;
#   - suggest a remedy that only works if the reader assumes a precedence rule,
#     or one that could leave the machine with no identity at all. Setting a key
#     is only ever proposed for a key nothing on the machine sets;
#   - write anything. It reads git's answer and reports it.
#
# Must stay bash 3.2 compatible - see AGENTS.md.

# Ask git what it resolves $1 to, and from where. Sets, for the caller to read
# immediately: GIT_IDENTITY_VALUE and GIT_IDENTITY_ORIGIN, both empty when git
# resolves the key to nothing. A non-file origin - git's own command line, a
# blob - is reported verbatim, since it is still what git answered.
#
# Asked from $HOME rather than the current directory, so the config of whatever
# repository the script happens to sit in is not read as a machine-wide one.
git_identity_lookup() {
  local key=$1 resolved
  GIT_IDENTITY_VALUE=""
  GIT_IDENTITY_ORIGIN=""
  resolved="$(git -C "$HOME" config --show-origin --get "$key" 2>/dev/null || true)"
  [ -n "$resolved" ] || return 0
  # `--show-origin` prints "<origin><TAB><value>". A value may itself contain a
  # tab, so split on the first one only.
  GIT_IDENTITY_ORIGIN="${resolved%%$'\t'*}"
  GIT_IDENTITY_VALUE="${resolved#*$'\t'}"
  case $GIT_IDENTITY_ORIGIN in
    file:*) GIT_IDENTITY_ORIGIN="${GIT_IDENTITY_ORIGIN#file:}" ;;
  esac
}

# Report what git resolves, or say nothing at all.
#
# Silence is the point on a correctly configured machine: rebuild.sh runs this
# on every switch, and a warning that prints every time is one nobody reads. So
# it speaks only when something is worth an interruption - no identity at all,
# or an identity coming from a file these scripts do not write.
#
# $1 is an optional indent, so bootstrap.sh's step margin is preserved.
git_identity_report() {
  local indent=${1:-}
  local managed="$HOME/.gitconfig.local"
  local name_value name_origin email_value email_origin

  git_identity_lookup user.name
  name_value=$GIT_IDENTITY_VALUE
  name_origin=$GIT_IDENTITY_ORIGIN
  git_identity_lookup user.email
  email_value=$GIT_IDENTITY_VALUE
  email_origin=$GIT_IDENTITY_ORIGIN

  if [ -n "$name_value" ] && [ -n "$email_value" ] \
    && [ "$name_origin" = "$managed" ] && [ "$email_origin" = "$managed" ]; then
    return 0
  fi

  if [ -z "$name_value" ] && [ -z "$email_value" ]; then
    git_identity_say "$indent" "Heads up: git resolves no user.name and no user.email here, so it"
    git_identity_say "$indent" "will invent an identity for whatever you commit next."
  else
    git_identity_say "$indent" "Heads up: git does not resolve your whole identity from ~/.gitconfig.local,"
    git_identity_say "$indent" "the one file this setup writes."
  fi

  git_identity_report_key "$indent" user.name "$name_value" "$name_origin"
  git_identity_report_key "$indent" user.email "$email_value" "$email_origin"

  # Proposed only for a key nothing on this machine sets, so the advice cannot
  # depend on which file would win, and cannot end up removing the only
  # identity the machine has.
  if [ -z "$name_value" ] || [ -z "$email_value" ]; then
    git_identity_say "$indent" "Set what git resolves to nothing with:"
    [ -n "$name_value" ] \
      || git_identity_say "$indent" "  git config --file ~/.gitconfig.local user.name \"Your Name\""
    [ -n "$email_value" ] \
      || git_identity_say "$indent" "  git config --file ~/.gitconfig.local user.email \"you@example.com\""
  fi

  git_identity_report_foreign_origin "$indent" "$managed" \
    "$name_value" "$name_origin" "$email_value" "$email_origin"
}

# One observation line per key: the value git resolved and the origin git named,
# or the plain fact that it resolved nothing. Each key on its own line, never
# assembled into an identity string.
git_identity_report_key() {
  local indent=$1 key=$2 value=$3 origin=$4
  if [ -z "$value" ]; then
    git_identity_say "$indent" "  git resolves no $key."
  else
    git_identity_say "$indent" "  git resolves $key to \"$value\", from $origin."
  fi
}

# Name the files these scripts do not own, once each, and leave them alone. No
# remedy is offered for them: the correct edit is the reader's call, in their
# own file, and anything more specific would be a claim about precedence.
git_identity_report_foreign_origin() {
  local indent=$1 managed=$2 name_value=$3 name_origin=$4 email_value=$5 email_origin=$6
  local foreign=""

  if [ -n "$name_value" ] && [ "$name_origin" != "$managed" ]; then
    foreign=$name_origin
  fi
  if [ -n "$email_value" ] && [ "$email_origin" != "$managed" ] \
    && [ "$email_origin" != "$foreign" ]; then
    if [ -n "$foreign" ]; then
      foreign="$foreign and $email_origin"
    else
      foreign=$email_origin
    fi
  fi
  [ -n "$foreign" ] || return 0

  git_identity_say "$indent" "These scripts write only ~/.gitconfig.local. They never change"
  git_identity_say "$indent" "$foreign; edit that yourself if that is not the identity you want."
}

# printf, not echo: an identity value is arbitrary text, and echo would eat a
# leading -n or -e.
git_identity_say() {
  printf '%s%s\n' "$1" "$2"
}
