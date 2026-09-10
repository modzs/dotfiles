#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=lib/dotfiles-link.sh
. "$DIR/lib/dotfiles-link.sh"
# shellcheck source=lib/git-identity.sh
. "$DIR/lib/git-identity.sh"

# Refuse before sudo, not after: the switch below builds ~/.dotfiles#mac.
dotfiles_link_apply "$DIR"

# The other thing worth refusing before sudo. Checking `command -v` here and
# then writing `sudo darwin-rebuild` would guard a different command than the
# one that runs: sudo resolves the name itself, through a PATH that need not be
# this shell's. Resolving the absolute path here and handing sudo that path
# makes the two the same question, so a guard that passes cannot be followed by
# `sudo: darwin-rebuild: command not found` after the user has typed a
# password. Do not collapse this back to `sudo darwin-rebuild`.
# `|| true` keeps the failing lookup from aborting the script under
# set -euo pipefail, so the guard below is what reports it.
DARWIN_REBUILD_BIN="$(command -v darwin-rebuild || true)"
if [ -z "$DARWIN_REBUILD_BIN" ]; then
  echo "darwin-rebuild is not on this shell's PATH, so the switch cannot run."
  echo "nix-darwin puts it on the PATH of shells opened after a switch, so a"
  echo "terminal that was already open when ./bootstrap.sh ran will not have it."
  echo "Open a new terminal and re-run ./rebuild.sh. If a new terminal has no"
  echo "darwin-rebuild either, this machine has not been switched yet: run"
  echo "./bootstrap.sh first."
  exit 1
fi

# Not `exec sudo`: the identity report below has to run after the switch, which
# is what installs home.nix's include of ~/.gitconfig.local. bootstrap.sh runs
# once and never prompts again, so a machine set up before the identity left the
# tracked config would otherwise lose it here without a word. The switch's own
# exit status is kept and re-raised, so a report can neither fail a good rebuild
# nor hide a failed one.
STATUS=0
sudo "$DARWIN_REBUILD_BIN" switch --flake ~/.dotfiles#mac || STATUS=$?

if [ "$STATUS" = 0 ]; then
  # `missing-only`: this runs on every single switch, so it speaks only about a
  # key git resolves to nothing and would guess. An identity deliberately kept
  # in another file is a correct setup, and bootstrap.sh already said so once.
  git_identity_report missing-only
else
  # Nothing else gets the last word after a failed switch. The report above is
  # friendly advice about git, and reading it as the closing line of a rebuild
  # that did not happen is how a failure gets mistaken for a success.
  echo "Rebuild failed: 'sudo darwin-rebuild switch' exited $STATUS."
  echo "Fix what it reported above, then re-run ./rebuild.sh."
fi

exit "$STATUS"
