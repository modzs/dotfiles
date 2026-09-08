#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=lib/dotfiles-link.sh
. "$DIR/lib/dotfiles-link.sh"
# shellcheck source=lib/git-identity.sh
. "$DIR/lib/git-identity.sh"

# Refuse before sudo, not after: the switch below builds ~/.dotfiles#mac.
dotfiles_link_apply "$DIR"

# Not `exec sudo`: the identity report below has to run after the switch, which
# is what installs home.nix's include of ~/.gitconfig.local. bootstrap.sh runs
# once and never prompts again, so a machine set up before the identity left the
# tracked config would otherwise lose it here without a word. The switch's own
# exit status is kept and re-raised, so a report can neither fail a good rebuild
# nor hide a failed one.
STATUS=0
sudo darwin-rebuild switch --flake ~/.dotfiles#mac || STATUS=$?

git_identity_report

exit "$STATUS"
