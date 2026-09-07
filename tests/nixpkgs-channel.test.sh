#!/usr/bin/env bash
# Behaviour tests for the nixpkgs input this flake tracks.
#
# The property under test is not which branch name appears in flake.nix. It is
# the thing the user actually feels: a routine ./rebuild.sh is served from the
# binary cache instead of compiling packages locally. So both checks ask the
# systems that really decide that, rather than reading the config as text:
#
# - channels.nixos.org, which only advances a channel pointer once Hydra has
#   finished that jobset and pushed the results to cache.nixos.org. A plain
#   release branch has no channel and therefore no such guarantee;
# - cache.nixos.org, which is queried for the exact store paths this flake
#   evaluates to. A path with no substitute there is a path nix compiles.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dotfiles_test_parse_args "$@"

# GET a URL, printing the body, and return non-zero on any non-2xx status.
fetch() { curl -sfL --max-time 30 "$1"; }

# True when cache.nixos.org can serve a prebuilt copy of a /nix/store path.
has_substitute() {
  local hash
  hash=$(basename "$1" | cut -d- -f1)
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
        "https://cache.nixos.org/$hash.narinfo")" = 200 ]
}

# --- the tracked ref must be a real, Hydra-verified channel -------------------
#
# flake.lock is the pinned, machine-consumed artifact that records which ref
# `nix flake update` follows, so it is parsed as JSON rather than scanned. What
# the check asserts is external: that channels.nixos.org publishes a revision
# for that ref. `release-26.05` does not have one - it is just a git branch
# that advances ahead of the Darwin jobset - which is exactly the state that
# used to send ./rebuild.sh off to compile.

test_nixpkgs_input_tracks_a_published_channel() {
  local ref rev
  if ! command -v node >/dev/null 2>&1; then
    skip "nixpkgs channel check (node not found)"
    return 0
  fi
  if ! fetch https://channels.nixos.org/ >/dev/null 2>&1; then
    skip "nixpkgs channel check (channels.nixos.org unreachable)"
    return 0
  fi

  ref=$(node -e '
    const fs = require("fs");
    const lock = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const nixpkgs = lock.nodes[lock.nodes.root.inputs.nixpkgs];
    const ref = nixpkgs && nixpkgs.original && nixpkgs.original.ref;
    if (!ref) { console.error("flake.lock pins no nixpkgs ref"); process.exit(1); }
    process.stdout.write(ref);
  ' "$ROOT/flake.lock") || fail "could not read the tracked nixpkgs ref from flake.lock"

  rev=$(fetch "https://channels.nixos.org/$ref/git-revision") \
    || fail "nixpkgs tracks '$ref', which publishes no channel revision: a rebuild can land on a commit Hydra has not built, and nix falls back to compiling locally"

  case $rev in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      : ;;
    *) fail "channel '$ref' did not publish a commit revision (got: $rev)" ;;
  esac

  pass "nixpkgs: tracked ref '$ref' is a published channel (cache-verified at $rev)"
}

# --- everything nixpkgs supplies must come prebuilt ---------------------------
#
# The point of tracking the darwin channel is that a rebuild fetches instead of
# compiles. This evaluates the flake - nix itself, on this machine's real host
# platform - down to the store paths the configuration installs, keeps the ones
# nixpkgs defines (Home Manager's own generated derivations are config-local
# and are never in any cache), and asks cache.nixos.org for each. Tracking a
# channel that was never built for this platform - the Linux `nixpkgs-26.05`,
# say - fails here.

test_nixpkgs_supplied_packages_are_all_prebuilt() {
  local paths path missing=0 count=0
  if ! command -v nix >/dev/null 2>&1; then
    skip "binary cache coverage of the installed packages (nix not found)"
    return 0
  fi
  if ! curl -sf --max-time 30 -o /dev/null https://cache.nixos.org/nix-cache-info; then
    skip "binary cache coverage of the installed packages (cache.nixos.org unreachable)"
    return 0
  fi

  # meta.position points at the file that defines a package, so a prefix of the
  # nixpkgs source tree is what identifies a package as coming from nixpkgs.
  paths=$(nix eval --raw --no-write-lock-file --apply 'cfg:
    let
      src = toString cfg.pkgs.path;
      installed = builtins.concatMap (u: u.home.packages)
        (builtins.attrValues cfg.config.home-manager.users);
      fromNixpkgs = builtins.filter
        (p: builtins.substring 0 (builtins.stringLength src) (p.meta.position or "") == src)
        installed;
    in builtins.concatStringsSep "\n" (map (p: p.outPath) fromNixpkgs)' \
    "$ROOT#darwinConfigurations.mac" 2>/dev/null) \
    || fail "could not evaluate the installed package set from the flake"
  [ -n "$paths" ] || fail "the flake evaluated no nixpkgs-supplied packages"

  for path in $paths; do
    count=$((count + 1))
    if ! has_substitute "$path"; then
      printf 'no substitute: %s\n' "$path" >&2
      missing=$((missing + 1))
    fi
  done

  [ "$missing" -eq 0 ] \
    || fail "$missing of $count nixpkgs packages have no prebuilt substitute, so ./rebuild.sh would compile them locally"

  pass "nixpkgs: all $count nixpkgs-supplied packages are prebuilt in the binary cache"
}

test_nixpkgs_input_tracks_a_published_channel
test_nixpkgs_supplied_packages_are_all_prebuilt

test_summary
