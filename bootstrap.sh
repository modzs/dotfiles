#!/usr/bin/env bash
# Bootstrap from nothing to a configured dotfiles setup on macOS.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=lib/dotfiles-link.sh
. "$DIR/lib/dotfiles-link.sh"
# shellcheck source=lib/git-identity.sh
. "$DIR/lib/git-identity.sh"

# Everything below resolves through ~/.dotfiles, so settle that path before
# anything is installed and before sudo is asked for. Refusing here costs the
# user nothing; refusing at step 6 would cost them a Nix install and a password.
echo "==> Preflight: ~/.dotfiles"
# A failing command substitution in an assignment exits under `set -e`, so an
# unusable ~/.dotfiles stops the script right here.
PREFLIGHT="$(dotfiles_link_check "$DIR")"
if [ "$PREFLIGHT" = already ]; then
  echo "    this repository already is ~/.dotfiles"
else
  echo "    ok"
fi

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
dotfiles_link_apply "$DIR"

echo "==> Step 3: personalize the configured username"
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: personalize the machine name"
CURRENT_NAME="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
FLAKE_HOSTNAME="$(sed -nE 's/^[[:space:]]*hostName = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_HOSTNAME" ]; then
  echo "    Could not find the single \"hostName = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
fi
echo "    This machine is currently named \"$CURRENT_NAME\"."
echo "    flake.nix is configured for \"$FLAKE_HOSTNAME\"."
read -r -p "    Machine name [$FLAKE_HOSTNAME]: " NEW_HOSTNAME || true
NEW_HOSTNAME="${NEW_HOSTNAME:-$FLAKE_HOSTNAME}"
if ! [[ "$NEW_HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
  echo "    \"$NEW_HOSTNAME\" is not a valid machine name."
  echo "    Use 1-63 letters, digits, or hyphens, starting and ending with a letter or digit."
  exit 1
fi
if [ "$NEW_HOSTNAME" != "$FLAKE_HOSTNAME" ]; then
  sed -i '' -E "s/^([[:space:]]*hostName = \")[^\"]+(\";.*)/\1${NEW_HOSTNAME}\2/" "$DIR/flake.nix"
  echo "    Updated flake.nix. Review the change with: git diff flake.nix"
else
  echo "    Keeping \"$FLAKE_HOSTNAME\"."
fi
# nix-darwin applies networking.hostName during the switch in step 6.
echo "    nix-darwin will apply this during the switch."

echo "==> Step 5: personalize the git identity"
# The identity lives in the untracked ~/.gitconfig.local, never in this repo:
# home.nix sets no name or email, it only pulls that file in through
# programs.git.includes. Writing the two keys with `git config --file` leaves
# anything else already in the file - work-machine overrides, say - untouched.
GITCONFIG_LOCAL="$HOME/.gitconfig.local"

# git's complaints run to several lines. Indent every one of them, so a quoted
# error stays visibly part of the step rather than breaking out of its margin.
echo_git_output() {
  printf '%s\n' "$1" | sed 's/^/      /'
}

# One wording for the file's contents, printed before the prompts and again
# after the writes, so the two can never disagree. Each key is reported on its
# own: half an identity rendered as "name <email>" reads as a whole one.
print_gitconfig_local_state() {
  local name=$1 email=$2
  if [ -n "$name" ] && [ -n "$email" ]; then
    echo "    ~/.gitconfig.local holds user.name \"$name\" and user.email \"$email\"."
  elif [ -n "$name" ]; then
    echo "    ~/.gitconfig.local holds user.name \"$name\" and no user.email."
  elif [ -n "$email" ]; then
    echo "    ~/.gitconfig.local holds user.email \"$email\" and no user.name."
  else
    echo "    ~/.gitconfig.local holds no user.name and no user.email."
  fi
}

# A hand-edited ~/.gitconfig.local can be unparsable, and then every read of it
# comes back empty - indistinguishable from a file that simply sets nothing.
# Ask git once, keep its complaint, and report that instead of a false "holds
# nothing".
GITCONFIG_LOCAL_ERROR=""
if [ -e "$GITCONFIG_LOCAL" ]; then
  GITCONFIG_LOCAL_ERROR="$(git config --file "$GITCONFIG_LOCAL" --list 2>&1 >/dev/null || true)"
fi
# Prefer what that file already says, and offer nothing otherwise: a default
# read from this machine's wider git config would propose whoever configured it
# before - including the identity this repo deliberately stopped shipping.
GIT_NAME="$(git config --file "$GITCONFIG_LOCAL" --get user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --file "$GITCONFIG_LOCAL" --get user.email 2>/dev/null || true)"
echo "    This step writes a git name and email to ~/.gitconfig.local, which"
echo "    lives outside this repo and is never committed."
if [ -n "$GITCONFIG_LOCAL_ERROR" ]; then
  echo "    git cannot parse ~/.gitconfig.local, so nothing can be read from it:"
  echo_git_output "$GITCONFIG_LOCAL_ERROR"
  echo "    Fix that file by hand; step 6 below runs either way."
else
  print_gitconfig_local_state "$GIT_NAME" "$GIT_EMAIL"
fi
read -r -p "    Git name [$GIT_NAME]: " NEW_GIT_NAME || true
NEW_GIT_NAME="${NEW_GIT_NAME:-$GIT_NAME}"
# Whatever is typed is taken as given. Nix is installed and flake.nix is already
# rewritten by now, so no answer may abort the run, and git validates neither
# key itself. An empty answer is a deliberate skip: home.nix's include handles
# an absent ~/.gitconfig.local.
read -r -p "    Git email [$GIT_EMAIL]: " NEW_GIT_EMAIL || true
NEW_GIT_EMAIL="${NEW_GIT_EMAIL:-$GIT_EMAIL}"
# Each key is written and reported on its own: a name typed without an email is
# still the user's answer, and one key git refuses says nothing about the other.
# A write git refuses - an unparsable file, or a duplicated [user] section it
# cannot collapse - carries git's own reason and is survived, never allowed to
# kill the run one step short of the switch.
WROTE=""
UNWRITABLE=""
write_identity_key() {
  local key=$1 value=$2 err status=0
  [ -n "$value" ] || return 0
  err="$(git config --file "$GITCONFIG_LOCAL" "$key" "$value" 2>&1 >/dev/null)" || status=$?
  if [ "$status" = 0 ]; then
    WROTE=yes
    echo "    Wrote $key to ~/.gitconfig.local."
    return 0
  fi
  UNWRITABLE=yes
  echo "    git refused to write $key to ~/.gitconfig.local:"
  [ -z "$err" ] || echo_git_output "$err"
  echo "    Repair that file by hand, then set that key with:"
  echo "      git config --file ~/.gitconfig.local $key \"$value\""
}
write_identity_key user.name "$NEW_GIT_NAME"
write_identity_key user.email "$NEW_GIT_EMAIL"
# Report the file, not the keystrokes. A prompt answered with Enter leaves
# whatever was already there, so only a fresh read says what the file holds now.
FINAL_GIT_NAME="$(git config --file "$GITCONFIG_LOCAL" --get user.name 2>/dev/null || true)"
FINAL_GIT_EMAIL="$(git config --file "$GITCONFIG_LOCAL" --get user.email 2>/dev/null || true)"
# What is still missing is left to the post-switch report below. That is the
# only moment the answer is final, and advice given before it is the defect this
# whole arrangement exists to remove.
if [ -z "$GITCONFIG_LOCAL_ERROR" ] && [ -z "$UNWRITABLE" ] && [ -n "$WROTE" ]; then
  print_gitconfig_local_state "$FINAL_GIT_NAME" "$FINAL_GIT_EMAIL"
fi
echo "==> Step 6: first build and switch"
# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight from
# the flake this once. After this, rebuild.sh works normally.
# This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
# not the exact flake.lock revision. The system config it applies is still
# pinned by this repo's flake.lock.
# sudo resets PATH to a secure default that excludes /nix/.../bin, so a freshly
# installed `nix` would not be found under sudo even though it is on PATH here.
# Resolve the absolute path first and invoke that instead - do not collapse this
# to `sudo nix run`.
# `|| true` keeps the lookup from aborting the script under set -euo pipefail,
# so the guard below is what reports a missing nix instead of a silent exit.
NIX_BIN="$(command -v nix || true)"
if [ -z "$NIX_BIN" ]; then
  echo "    nix is not on this shell's PATH, so the switch cannot run."
  echo "    The Determinate installer only adds nix to the PATH of new shells,"
  echo "    so a terminal opened before step 1 installed it will not have it."
  echo "    Open a new terminal and re-run ./bootstrap.sh."
  exit 1
fi
# "mac" is the flake output name, a stable config identifier. It is deliberately
# separate from the machine name set in step 4; if you rename it, change it in
# flake.nix and rebuild.sh too.
sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake ~/.dotfiles#mac

# Only now is the answer final: the switch is what installs home.nix's include
# of ~/.gitconfig.local, so before it git could not have read the file step 5
# just wrote. Asked any earlier, this reported a conflict that the switch itself
# then resolved. It stays silent unless something is worth saying.
#
# `full`: this is the one run that also names the file behind an identity that
# resolves from somewhere other than ~/.gitconfig.local. rebuild.sh would say
# that on every switch forever, so it does not.
git_identity_report full "    "

echo "==> Done. Use ./rebuild.sh for future changes."
