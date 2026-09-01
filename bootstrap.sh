#!/usr/bin/env bash
# Bootstrap from nothing to a configured dotfiles setup.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="darwin"
  FLAKE_HOST="mac"
else
  OS="linux"
  FLAKE_HOST="omarchy"
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
ln -sfn "$DIR" ~/.dotfiles

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
    if [[ "$OS" == "darwin" ]]; then
      sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    else
      sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    fi
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: personalize the machine name"
if [[ "$OS" == "darwin" ]]; then
  CURRENT_NAME="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
else
  CURRENT_NAME="$(hostname -s)"
fi
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
  if [[ "$OS" == "darwin" ]]; then
    sed -i '' -E "s/^([[:space:]]*hostName = \")[^\"]+(\";.*)/\1${NEW_HOSTNAME}\2/" "$DIR/flake.nix"
  else
    sed -i -E "s/^([[:space:]]*hostName = \")[^\"]+(\";.*)/\1${NEW_HOSTNAME}\2/" "$DIR/flake.nix"
  fi
  echo "    Updated flake.nix. Review the change with: git diff flake.nix"
else
  echo "    Keeping \"$FLAKE_HOSTNAME\"."
fi

if [[ "$OS" == "darwin" ]]; then
  # nix-darwin applies networking.hostName during the switch in step 5.
  echo "    macOS: nix-darwin will apply this during the switch."
elif [ "$NEW_HOSTNAME" != "$CURRENT_NAME" ]; then
  # home-manager is user-level only and cannot set the system hostname,
  # so apply it directly here.
  echo "    Linux: setting the system hostname (needs sudo)..."
  sudo hostnamectl set-hostname "$NEW_HOSTNAME"
fi

echo "==> Step 5: first build and switch"
NIX_BIN="$(command -v nix)"

if [[ "$OS" == "darwin" ]]; then
  echo "    Using darwin-rebuild for macOS..."
  sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
    switch --flake ~/.dotfiles#mac
else
  echo "    Using home-manager for Linux..."
  "$NIX_BIN" run home-manager/release-26.05 -- switch --flake ~/.dotfiles#omarchy
fi

echo "==> Done. Use ./rebuild.sh for future changes."
