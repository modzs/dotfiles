#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=lib/dotfiles-link.sh
. "$DIR/lib/dotfiles-link.sh"

# Refuse before sudo, not after: the switch below builds ~/.dotfiles#mac.
dotfiles_link_apply "$DIR"

exec sudo darwin-rebuild switch --flake ~/.dotfiles#mac
