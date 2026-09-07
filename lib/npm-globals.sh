#!/usr/bin/env bash
# lib/npm-globals.sh - install the pinned agent CLIs that are not in nixpkgs.
#
# Called by `home.activation.agentNpmCLIs` in home.nix on every switch. It used
# to be a Nix string inlined there, which meant the most intricate logic in the
# repo - the one step that runs on every single rebuild - could not be executed
# by a test. It lives here for the same reason lib/dotfiles-link.sh does.
#
#   npm-globals.sh <node-bin-dir> <npm-prefix> <name@version>...
#
# The pinned versions are arguments, never baked in here: `npmGlobals` in
# home.nix stays the single source of truth for what is pinned.
#
# Contract, which tests/npm-globals.test.sh pins down:
#   - a spec whose installed version already matches is skipped, so a rebuild
#     with nothing to change touches the network zero times;
#   - anything else is installed at exactly the pinned version, into the given
#     prefix;
#   - a failed install warns and the script still succeeds, so a switch is
#     never aborted by an offline machine;
#   - with DRY_RUN set, it reports what it would install and installs nothing.
#
# Must stay bash 3.2 compatible - see AGENTS.md.
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: npm-globals.sh <node-bin-dir> <npm-prefix> <name@version>..." >&2
  exit 2
fi

nodeBin=$1
npmPrefix=$2
shift 2

for spec in "$@"; do
  name="${spec%@*}"
  want="${spec##*@}"
  manifest="$npmPrefix/lib/node_modules/$name/package.json"

  have=""
  if [ -r "$manifest" ]; then
    have="$("$nodeBin/node" -p "require('$manifest').version" 2>/dev/null || true)"
  fi
  if [ "$have" = "$want" ]; then
    continue
  fi

  if [ -n "${DRY_RUN+x}" ]; then
    echo "would install $spec into $npmPrefix"
    continue
  fi

  echo "installing $spec into $npmPrefix"
  if ! PATH="$nodeBin:$PATH" NPM_CONFIG_PREFIX="$npmPrefix" \
       "$nodeBin/npm" install --global --no-fund --no-audit "$spec"; then
    echo "warning: could not install $spec (offline?). Keeping ${have:-nothing}." >&2
  fi
done

exit 0
