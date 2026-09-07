#!/usr/bin/env bash
# Behaviour tests for what this repository tracks and what it declares.
#
# Both checks run the real consumer of the artifact under test rather than
# reading it as text: git decides what .gitignore and the index mean, and a
# real JSON parser decides what Pi's settings.json declares.
#
# Coverage:
# - the herdr runtime artifacts (~/.config/herdr is an out-of-store symlink
#   into this repo, so everything herdr writes lands in the working tree);
# - the package sources Pi installs from the linked global settings.json.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dotfiles_test_parse_args "$@"

# --- herdr runtime artifacts --------------------------------------------------
#
# home.nix links ~/.config/herdr straight at home/.config/herdr with
# mkOutOfStoreSymlink, so a running herdr writes its release notes, plugin
# lock, session state, logs and sockets directly into the git working tree.
# Any of those that the repo also tracks turns every herdr run into an
# unexplained `git status` diff the user has to clean up by hand.

test_herdr_runtime_artifacts_never_dirty_the_repo() {
  local sb tracked file dirty
  sb=$(dotfiles_test_tmproot dotfiles-herdr)

  # Reproduce this repo's committed state for the herdr directory in a scratch
  # repository: the working tree's .gitignore, plus every file the real repo
  # tracks under home/.config/herdr.
  git -C "$sb" init -q
  cp "$ROOT/.gitignore" "$sb/.gitignore"
  mkdir -p "$sb/home/.config/herdr"
  tracked=$(git -C "$ROOT" ls-files home/.config/herdr)
  for file in $tracked; do
    mkdir -p "$sb/$(dirname "$file")"
    cp "$ROOT/$file" "$sb/$file"
  done
  git -C "$sb" add -A
  git -C "$sb" -c user.name=dotfiles-test -c user.email=dotfiles-test@example.invalid \
    commit -qm "committed herdr state"

  # Now write what a herdr run actually leaves behind. The contents differ from
  # anything that could have been committed, so a tracked artifact shows up as a
  # modification rather than hiding behind identical bytes.
  printf '{"version":"0.0.0-test","body":"regenerated at runtime","show_on_startup":true}' \
    >"$sb/home/.config/herdr/release-notes.json"
  : >"$sb/home/.config/herdr/.plugins.lock"
  printf '{"session":"test"}' >"$sb/home/.config/herdr/session.json"
  printf 'runtime log line\n' >"$sb/home/.config/herdr/herdr-server.log"
  printf 'runtime log line\n' >"$sb/home/.config/herdr/herdr-client.log"
  : >"$sb/home/.config/herdr/herdr.sock"

  dirty=$(git -C "$sb" status --porcelain)
  [ -z "$dirty" ] \
    || fail "a herdr run dirties the repository: $(printf '%s' "$dirty" | tr '\n' ' ')"

  pass "herdr: a full set of runtime artifacts leaves the working tree clean"
}

# --- Pi package sources -------------------------------------------------------
#
# Pi installs every source listed in the linked global settings.json at startup,
# with the user's full permissions. README.md commits to immutable pins only, so
# an unpinned range or a mutable git ref must not be able to slip in unnoticed.

test_pi_declares_only_immutable_npm_pins() {
  if ! command -v node >/dev/null 2>&1; then
    skip "Pi package source check (node not found)"
    return 0
  fi

  node -e '
    const fs = require("fs");
    const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const packages = settings.packages;
    if (!Array.isArray(packages)) {
      console.error("settings.json declares no packages array");
      process.exit(1);
    }
    // npm:<name>@<exact semver>, where <name> may be scoped (@scope/name).
    const pinned = /^npm:(@[^/@]+\/)?[^@/]+@\d+\.\d+\.\d+$/;
    const bad = packages.filter((p) => typeof p !== "string" || !pinned.test(p));
    if (bad.length) {
      console.error("not an immutable npm pin: " + bad.join(", "));
      process.exit(1);
    }
  ' "$ROOT/home/.pi/agent/settings.json" || fail "Pi declares a package source that is not an immutable npm pin"

  pass "pi: every declared package source is an immutable npm pin"
}

test_herdr_runtime_artifacts_never_dirty_the_repo
test_pi_declares_only_immutable_npm_pins

test_summary
