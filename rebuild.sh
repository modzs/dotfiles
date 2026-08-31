#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles

if [[ "$OSTYPE" == "darwin"* ]]; then
  exec sudo darwin-rebuild switch --flake ~/.dotfiles#mac
else
  exec nix run home-manager/release-26.05 -- switch --flake ~/.dotfiles#omarchy
fi
