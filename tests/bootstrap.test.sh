#!/usr/bin/env bash
# Behaviour tests for bootstrap.sh and rebuild.sh.
#
# Every case runs the real, unmodified scripts against a sandboxed $HOME inside
# a temp directory, with PATH shims for sudo, nix and scutil that record their
# arguments instead of executing. Nothing here touches the real $HOME, the real
# ~/.dotfiles, Nix, or Homebrew.
#
# Coverage:
# - the ~/.dotfiles link: absent, a stale symlink, an already-correct symlink,
#   the repo cloned to ~/.dotfiles itself, an unrelated real directory, and a
#   real file - for both bootstrap.sh and rebuild.sh;
# - the personalization matrix: username match, mismatch answered y, mismatch
#   answered n, a valid machine name, an invalid machine name, and empty input
#   keeping the configured default;
# - the git identity prompt: a new identity written to ~/.gitconfig.local, empty
#   input keeping the identity already there, a name typed without an email, a
#   malformed email taken as typed instead of aborting, a file holding only one
#   of the two keys, no default offered from the wider git config, an existing
#   ~/.gitconfig.local keeping its unrelated contents, a ~/.gitconfig setting a
#   key the new identity also sets, and an unparsable ~/.gitconfig.local that
#   must not abort the run.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dotfiles_test_parse_args "$@"

TMP_ROOT=$(dotfiles_test_tmproot dotfiles-bootstrap)

# --- sandbox -----------------------------------------------------------------

# Build a disposable sandbox and echo its root. Layout:
#   <sb>/home            the fake $HOME
#   <sb>/repo            a copy of the working tree (the default repo location)
#   <sb>/bin             sudo / nix / scutil shims
#   <sb>/calls.log       every shim invocation, in order
# $1 (optional) is the path the repo copy should live at, relative to <sb>.
make_sandbox() {
  local repo_rel=${1:-repo} sb
  # mktemp, not a counter: make_sandbox is called inside a command
  # substitution, so any variable it increments would only change in the
  # subshell and every case would collide on the same directory.
  sb=$(mktemp -d "$TMP_ROOT/case.XXXXXX") || fail "could not create a sandbox"
  # Never build a sandbox at a path we did not just create: an empty $sb would
  # turn every path below into an absolute one and write to the real root.
  case $sb in
    "$TMP_ROOT"/*) [ -d "$sb" ] || fail "sandbox $sb was not created" ;;
    *) fail "sandbox path escaped the test temp root: '$sb'" ;;
  esac
  mkdir -p "$sb/home" "$sb/bin" "$sb/$repo_rel"

  # Copy the working tree, not a git clone: these tests must exercise the
  # scripts as they are right now, including uncommitted edits.
  ( cd "$ROOT" && tar -cf - --exclude ./.git --exclude ./.no-mistakes . ) \
    | ( cd "$sb/$repo_rel" && tar -xf - )

  # The link and machine-name cases are not about the username, and whoever
  # runs the suite is usually not the user flake.nix declares - CI least of
  # all. Normalize it so those cases reach the step they are actually testing;
  # the username cases set it back to whatever they need.
  sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1$(whoami)\2/" \
    "$sb/$repo_rel/flake.nix"

  cat >"$sb/bin/sudo" <<SHIM
#!/bin/sh
echo "sudo \$*" >>"$sb/calls.log"
exit 0
SHIM
  # A nix shim guarantees bootstrap.sh takes its "already installed" branch, so
  # no test can ever reach the Determinate installer download.
  cat >"$sb/bin/nix" <<SHIM
#!/bin/sh
echo "nix \$*" >>"$sb/calls.log"
exit 0
SHIM
  cat >"$sb/bin/scutil" <<SHIM
#!/bin/sh
echo "scutil \$*" >>"$sb/calls.log"
[ "\$1 \$2" = "--get ComputerName" ] && echo SandboxMac
exit 0
SHIM
  cat >"$sb/bin/darwin-rebuild" <<SHIM
#!/bin/sh
echo "darwin-rebuild \$*" >>"$sb/calls.log"
exit 0
SHIM
  chmod +x "$sb/bin/sudo" "$sb/bin/nix" "$sb/bin/scutil" "$sb/bin/darwin-rebuild"

  printf '%s\n' "$sb"
}

# Run one of the repo's scripts inside a sandbox.
#   $1 sandbox root, $2 script path relative to the repo copy,
#   $3 repo path relative to the sandbox, $4 stdin to feed
# Writes combined output to <sb>/out and echoes the exit status.
run_script() {
  local sb=$1 script=$2 repo_rel=$3 input=$4 status=0
  # Belt and braces: never run with anything but the sandbox as $HOME.
  case "$sb/home" in
    "$TMP_ROOT"/*) : ;;
    *) fail "refusing to run with \$HOME outside the test temp root" ;;
  esac
  # git reads /etc/gitconfig and $XDG_CONFIG_HOME/git/config as well as $HOME,
  # so pin both into the sandbox: an identity on the runner's own machine must
  # never decide what these cases observe.
  printf '%s' "$input" \
    | env HOME="$sb/home" PATH="$sb/bin:$PATH" \
        GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$sb/home/.config" \
        /bin/bash "$sb/$repo_rel/$script" \
      >"$sb/out" 2>&1 || status=$?
  printf '%s\n' "$status"
}

run_bootstrap() {
  run_script "$1" bootstrap.sh "${2:-repo}" "${3:-$'\n'}"
}

sandbox_out() { cat "$1/out"; }
sandbox_calls() { cat "$1/calls.log" 2>/dev/null || true; }

# --- the ~/.dotfiles link (finding H1) ---------------------------------------

test_link_created_when_absent() {
  local sb status
  sb=$(make_sandbox)
  status=$(run_bootstrap "$sb")

  [ "$status" = 0 ] || fail "bootstrap failed with an absent ~/.dotfiles: $(sandbox_out "$sb")"
  [ -L "$sb/home/.dotfiles" ] || fail "bootstrap did not create ~/.dotfiles as a symlink"
  [ "$(cd "$sb/home/.dotfiles" && pwd -P)" = "$(cd "$sb/repo" && pwd -P)" ] \
    || fail "the ~/.dotfiles link does not resolve to the repo"
  # bootstrap.sh writes `--flake ~/.dotfiles#mac`, and the shell expands the
  # tilde to the sandbox $HOME before the shim ever sees it.
  assert_contains "$(sandbox_calls "$sb")" "switch --flake $sb/home/.dotfiles#mac" \
    "bootstrap did not reach the switch"

  pass "link: an absent ~/.dotfiles becomes a symlink to the repo"
}

test_link_rerun_is_idempotent() {
  local sb status
  sb=$(make_sandbox)
  status=$(run_bootstrap "$sb")
  [ "$status" = 0 ] || fail "first bootstrap run failed: $(sandbox_out "$sb")"
  status=$(run_bootstrap "$sb")

  [ "$status" = 0 ] || fail "second bootstrap run failed: $(sandbox_out "$sb")"
  [ -L "$sb/home/.dotfiles" ] || fail "the ~/.dotfiles link stopped being a symlink on re-run"
  [ "$(cd "$sb/home/.dotfiles" && pwd -P)" = "$(cd "$sb/repo" && pwd -P)" ] \
    || fail "the ~/.dotfiles link no longer resolves to the repo after a re-run"

  pass "link: an already-correct ~/.dotfiles symlink survives a re-run unchanged"
}

test_link_replaces_stale_symlink() {
  local sb status
  sb=$(make_sandbox)
  mkdir -p "$sb/somewhere-else"
  ln -sfn "$sb/somewhere-else" "$sb/home/.dotfiles"
  status=$(run_bootstrap "$sb")

  [ "$status" = 0 ] || fail "bootstrap failed against a stale symlink: $(sandbox_out "$sb")"
  [ "$(cd "$sb/home/.dotfiles" && pwd -P)" = "$(cd "$sb/repo" && pwd -P)" ] \
    || fail "a stale ~/.dotfiles symlink was not repointed at the repo"

  pass "link: a stale ~/.dotfiles symlink is repointed at the repo"
}

# The regression that matters most: cloning to ~/.dotfiles is the most natural
# install and the path both documents tell you to cd into. The old
# `ln -sfn "$DIR" ~/.dotfiles` exited 0 while planting ~/.dotfiles/dotfiles ->
# ~/.dotfiles, a self-referential symlink inside the user's own git tree.
test_link_when_repo_already_is_dotfiles() {
  local sb status
  sb=$(make_sandbox home/.dotfiles)
  status=$(run_bootstrap "$sb" home/.dotfiles)

  [ "$status" = 0 ] || fail "bootstrap failed when the repo is ~/.dotfiles: $(sandbox_out "$sb")"
  [ -d "$sb/home/.dotfiles" ] && [ ! -L "$sb/home/.dotfiles" ] \
    || fail "bootstrap turned the repo at ~/.dotfiles into a symlink"
  [ -z "$(find "$sb/home/.dotfiles" -maxdepth 1 -type l)" ] \
    || fail "bootstrap planted a symlink inside the repo at ~/.dotfiles"
  assert_contains "$(sandbox_out "$sb")" "already is ~/.dotfiles" \
    "bootstrap did not report that the repo already is ~/.dotfiles"
  assert_contains "$(sandbox_calls "$sb")" "switch --flake $sb/home/.dotfiles#mac" \
    "bootstrap did not reach the switch when the repo is ~/.dotfiles"

  pass "link: a repo cloned to ~/.dotfiles needs no link and bootstrap continues"
}

# The other half of H1: a pre-existing, unrelated ~/.dotfiles used to be
# accepted silently, and bootstrap died at step 5 - after installing Nix and
# taking the user's sudo password - with "could not find a flake.nix file".
test_link_refuses_unrelated_directory() {
  local sb status
  sb=$(make_sandbox)
  mkdir -p "$sb/home/.dotfiles/somethingelse"
  status=$(run_bootstrap "$sb")

  [ "$status" != 0 ] || fail "bootstrap accepted an unrelated ~/.dotfiles directory"
  assert_contains "$(sandbox_out "$sb")" "already exists and is not a symlink" \
    "bootstrap did not explain why it refused"
  assert_not_contains "$(sandbox_out "$sb")" "Step 1" \
    "bootstrap refused only after starting the Nix step"
  [ -z "$(sandbox_calls "$sb")" ] \
    || fail "bootstrap ran a privileged or external command before refusing: $(sandbox_calls "$sb")"
  [ -d "$sb/home/.dotfiles/somethingelse" ] \
    || fail "bootstrap disturbed the existing ~/.dotfiles directory"
  [ -z "$(find "$sb/home/.dotfiles" -maxdepth 1 -type l)" ] \
    || fail "bootstrap created a symlink inside the existing ~/.dotfiles directory"

  pass "link: an unrelated ~/.dotfiles directory is refused before Nix and before sudo"
}

test_link_refuses_regular_file() {
  local sb status
  sb=$(make_sandbox)
  printf 'not a directory\n' >"$sb/home/.dotfiles"
  status=$(run_bootstrap "$sb")

  [ "$status" != 0 ] || fail "bootstrap accepted a regular file at ~/.dotfiles"
  assert_contains "$(sandbox_out "$sb")" "already exists and is not a symlink" \
    "bootstrap did not explain why it refused a regular file"
  [ -z "$(sandbox_calls "$sb")" ] \
    || fail "bootstrap ran a privileged or external command before refusing"

  pass "link: a regular file at ~/.dotfiles is refused before Nix and before sudo"
}

test_rebuild_refuses_unrelated_directory() {
  local sb status
  sb=$(make_sandbox)
  mkdir -p "$sb/home/.dotfiles/somethingelse"
  status=$(run_script "$sb" rebuild.sh repo "")

  [ "$status" != 0 ] || fail "rebuild.sh accepted an unrelated ~/.dotfiles directory"
  assert_contains "$(sandbox_out "$sb")" "already exists and is not a symlink" \
    "rebuild.sh did not explain why it refused"
  [ -z "$(sandbox_calls "$sb")" ] \
    || fail "rebuild.sh reached sudo despite an unusable ~/.dotfiles"

  pass "rebuild: an unrelated ~/.dotfiles directory is refused before sudo"
}

test_rebuild_when_repo_already_is_dotfiles() {
  local sb status
  sb=$(make_sandbox home/.dotfiles)
  status=$(run_script "$sb" rebuild.sh home/.dotfiles "")

  [ "$status" = 0 ] || fail "rebuild.sh failed when the repo is ~/.dotfiles: $(sandbox_out "$sb")"
  [ -z "$(find "$sb/home/.dotfiles" -maxdepth 1 -type l)" ] \
    || fail "rebuild.sh planted a symlink inside the repo at ~/.dotfiles"
  assert_contains "$(sandbox_calls "$sb")" "sudo darwin-rebuild switch --flake $sb/home/.dotfiles#mac" \
    "rebuild.sh did not reach the switch when the repo is ~/.dotfiles"

  pass "rebuild: a repo cloned to ~/.dotfiles needs no link and the switch still runs"
}

# --- personalization ----------------------------------------------------------

flake_value() {
  sed -nE "s/^[[:space:]]*$2 = \"([^\"]+)\";.*/\1/p" "$1/repo/flake.nix" | head -n1
}

set_flake_user() {
  sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1$2\2/" "$1/repo/flake.nix"
}

test_username_match_leaves_flake_alone() {
  local sb status
  sb=$(make_sandbox)
  set_flake_user "$sb" "$(whoami)"
  status=$(run_bootstrap "$sb")

  [ "$status" = 0 ] || fail "bootstrap failed with a matching username: $(sandbox_out "$sb")"
  assert_contains "$(sandbox_out "$sb")" "nothing to do" \
    "bootstrap did not report the username as already correct"
  [ "$(flake_value "$sb" user)" = "$(whoami)" ] || fail "the user line changed unexpectedly"

  pass "personalize: a matching username prompts for nothing and rewrites nothing"
}

test_username_mismatch_accepted_rewrites_flake() {
  local sb status
  sb=$(make_sandbox)
  set_flake_user "$sb" someoneelse
  status=$(run_bootstrap "$sb" repo "y
"
)

  [ "$status" = 0 ] || fail "bootstrap failed after accepting the username rewrite: $(sandbox_out "$sb")"
  [ "$(flake_value "$sb" user)" = "$(whoami)" ] \
    || fail "answering y did not rewrite the user line to $(whoami)"

  pass "personalize: a username mismatch answered y rewrites the user line"
}

test_username_mismatch_declined_aborts() {
  local sb status
  sb=$(make_sandbox)
  set_flake_user "$sb" someoneelse
  status=$(run_script "$sb" bootstrap.sh repo "n
"
)

  [ "$status" != 0 ] || fail "bootstrap continued after the username rewrite was declined"
  assert_contains "$(sandbox_out "$sb")" "Edit the single \"user = \" line" \
    "bootstrap did not print the manual-edit guidance"
  [ "$(flake_value "$sb" user)" = someoneelse ] \
    || fail "answering n still rewrote the user line"
  [ -z "$(sandbox_calls "$sb")" ] || fail "bootstrap reached sudo after being declined"

  pass "personalize: a username mismatch answered n aborts without rewriting flake.nix"
}

test_machine_name_valid_is_written() {
  local sb status
  sb=$(make_sandbox)
  status=$(run_bootstrap "$sb" repo "work-laptop
"
)

  [ "$status" = 0 ] || fail "bootstrap failed with a valid machine name: $(sandbox_out "$sb")"
  [ "$(flake_value "$sb" hostName)" = work-laptop ] \
    || fail "the hostName line was not rewritten to work-laptop"

  pass "personalize: a valid machine name is written to the hostName line"
}

test_machine_name_invalid_aborts() {
  local sb status before
  sb=$(make_sandbox)
  before=$(flake_value "$sb" hostName)
  status=$(run_bootstrap "$sb" repo "bad name!
"
)

  [ "$status" != 0 ] || fail "bootstrap accepted an invalid machine name"
  assert_contains "$(sandbox_out "$sb")" "is not a valid machine name" \
    "bootstrap did not explain why the machine name was rejected"
  [ "$(flake_value "$sb" hostName)" = "$before" ] \
    || fail "an invalid machine name was written to flake.nix anyway"
  # Step 4 legitimately calls scutil before validating, so assert on sudo only.
  assert_not_contains "$(sandbox_calls "$sb")" "sudo " \
    "bootstrap reached sudo with an invalid machine name"

  pass "personalize: an invalid machine name aborts before writing anything"
}

test_machine_name_empty_keeps_default() {
  local sb status before
  sb=$(make_sandbox)
  before=$(flake_value "$sb" hostName)
  status=$(run_bootstrap "$sb")

  [ "$status" = 0 ] || fail "bootstrap failed on an empty machine name: $(sandbox_out "$sb")"
  assert_contains "$(sandbox_out "$sb")" "Keeping \"$before\"" \
    "bootstrap did not report that it kept the configured machine name"
  [ "$(flake_value "$sb" hostName)" = "$before" ] \
    || fail "empty input changed the hostName line"

  pass "personalize: empty input keeps the machine name configured in flake.nix"
}

# --- git identity (written to ~/.gitconfig.local, never to the repo) ----------

# Feed the whole prompt sequence of a run whose username already matches:
# machine name, git name, git email - each read exactly once, in that order.
identity_input() {
  local line
  for line in "$@"; do printf '%s\n' "$line"; done
}

gitconfig_local_value() {
  git config --file "$1/home/.gitconfig.local" --get "$2" 2>/dev/null || true
}

test_identity_written_to_gitconfig_local() {
  local sb status
  sb=$(make_sandbox)
  status=$(run_bootstrap "$sb" repo "$(identity_input '' 'Ada Lovelace' 'ada@example.com')")

  [ "$status" = 0 ] || fail "bootstrap failed while setting a git identity: $(sandbox_out "$sb")"
  [ "$(gitconfig_local_value "$sb" user.name)" = "Ada Lovelace" ] \
    || fail "the git name was not written to ~/.gitconfig.local"
  [ "$(gitconfig_local_value "$sb" user.email)" = "ada@example.com" ] \
    || fail "the git email was not written to ~/.gitconfig.local"
  # The whole point: the identity must never land in the tracked config, in any
  # spelling - so compare the whole file against the pristine tracked one.
  cmp -s "$sb/repo/home.nix" "$ROOT/home.nix" \
    || fail "bootstrap modified the tracked home.nix while setting the git identity"

  pass "identity: a new name and email are written to ~/.gitconfig.local"
}

test_identity_empty_keeps_existing() {
  local sb status
  sb=$(make_sandbox)
  git config --file "$sb/home/.gitconfig.local" user.name "Grace Hopper"
  git config --file "$sb/home/.gitconfig.local" user.email "grace@example.com"
  status=$(run_bootstrap "$sb" repo "$(identity_input '' '' '')")

  [ "$status" = 0 ] || fail "bootstrap failed on an empty git identity: $(sandbox_out "$sb")"
  assert_contains "$(sandbox_out "$sb")" "holds user.name \"Grace Hopper\" and user.email \"grace@example.com\"" \
    "bootstrap did not report the existing identity before prompting"
  assert_contains "$(sandbox_out "$sb")" "holds user.name \"Grace Hopper\" and user.email \"grace@example.com\"" \
    "bootstrap did not keep the existing identity on empty input"
  [ "$(gitconfig_local_value "$sb" user.name)" = "Grace Hopper" ] \
    || fail "empty input changed the existing git name"
  [ "$(gitconfig_local_value "$sb" user.email)" = "grace@example.com" ] \
    || fail "empty input changed the existing git email"

  pass "identity: empty input keeps the identity already in ~/.gitconfig.local"
}

# ~/.gitconfig.local is the documented home for work-machine overrides, so the
# prompt must set two keys inside it, not rewrite the file.
test_identity_preserves_unrelated_gitconfig_local() {
  local sb status
  sb=$(make_sandbox)
  git config --file "$sb/home/.gitconfig.local" user.name "Grace Hopper"
  git config --file "$sb/home/.gitconfig.local" user.email "grace@example.com"
  git config --file "$sb/home/.gitconfig.local" core.editor "emacs"
  git config --file "$sb/home/.gitconfig.local" commit.gpgsign true
  status=$(run_bootstrap "$sb" repo "$(identity_input '' 'Ada Lovelace' 'ada@example.com')")

  [ "$status" = 0 ] || fail "bootstrap failed against an existing ~/.gitconfig.local: $(sandbox_out "$sb")"
  [ "$(gitconfig_local_value "$sb" user.email)" = "ada@example.com" ] \
    || fail "the new identity did not reach an existing ~/.gitconfig.local"
  [ "$(gitconfig_local_value "$sb" core.editor)" = emacs ] \
    || fail "bootstrap dropped an unrelated setting from ~/.gitconfig.local"
  [ "$(gitconfig_local_value "$sb" commit.gpgsign)" = true ] \
    || fail "bootstrap dropped an unrelated setting from ~/.gitconfig.local"

  pass "identity: an existing ~/.gitconfig.local keeps its unrelated settings"
}

# Nix is installed and flake.nix rewritten by the time this prompt runs, so no
# answer may abort the run. git validates user.email no further than this does,
# so an odd-looking address is taken at its word rather than argued with.
test_identity_malformed_email_is_taken_as_typed() {
  local sb status
  sb=$(make_sandbox)
  status=$(run_bootstrap "$sb" repo "$(identity_input '' 'Ada Lovelace' 'not-an-email')")

  [ "$status" = 0 ] || fail "bootstrap aborted on a malformed git email: $(sandbox_out "$sb")"
  [ "$(gitconfig_local_value "$sb" user.email)" = "not-an-email" ] \
    || fail "bootstrap did not write the email exactly as it was typed"
  assert_contains "$(sandbox_calls "$sb")" "switch --flake $sb/home/.dotfiles#mac" \
    "bootstrap did not reach the switch after a malformed email"

  pass "identity: a malformed email is written as typed and never aborts the run"
}

# A value the user typed must never vanish: git itself reports the missing half
# at commit time, which beats silently discarding the half that was given.
test_identity_name_without_email_is_kept() {
  local sb status
  sb=$(make_sandbox)
  status=$(run_bootstrap "$sb" repo "$(identity_input '' 'Ada Lovelace' '')")

  [ "$status" = 0 ] || fail "bootstrap failed on a name without an email: $(sandbox_out "$sb")"
  [ "$(gitconfig_local_value "$sb" user.name)" = "Ada Lovelace" ] \
    || fail "bootstrap discarded a git name typed without an email"
  [ -z "$(gitconfig_local_value "$sb" user.email)" ] \
    || fail "bootstrap invented a git email that was never typed"
  assert_contains "$(sandbox_out "$sb")" "Wrote user.name to ~/.gitconfig.local." \
    "bootstrap did not report which identity key it wrote"
  assert_contains "$(sandbox_out "$sb")" "holds user.name \"Ada Lovelace\" and no user.email" \
    "bootstrap did not name the half ~/.gitconfig.local is missing"

  pass "identity: a name typed without an email is still written"
}


# Half an identity must never be rendered as a whole one: a file holding only an
# email once printed `commits as " <work@corp.example>"` before the prompts and
# `holds user.email ... and no user.name` after them, in the same run.
test_identity_half_set_file_is_reported_key_by_key() {
  local sb status
  sb=$(make_sandbox)
  git config --file "$sb/home/.gitconfig.local" user.email "work@corp.example"
  status=$(run_bootstrap "$sb" repo "$(identity_input '' '' '')")

  [ "$status" = 0 ] || fail "bootstrap failed on a half-set identity: $(sandbox_out "$sb")"
  assert_not_contains "$(sandbox_out "$sb")" "<work@corp.example>" \
    "bootstrap rendered a missing name inside a full identity string"
  assert_contains "$(sandbox_out "$sb")" "holds user.email \"work@corp.example\" and no user.name" \
    "bootstrap did not name the half ~/.gitconfig.local is missing"
  [ -z "$(gitconfig_local_value "$sb" user.name)" ] \
    || fail "empty input invented a git name"

  pass "identity: a file holding one key is reported key by key, not as an identity"
}

# Another config file can set the same key, one key at a time - a [user] section
# holding only an email yields a name from one file and an email from another.
# The run must name that file per key and leave it alone.
test_identity_competing_gitconfig_is_reported() {
  local sb status before
  sb=$(make_sandbox)
  cat >"$sb/home/.gitconfig" <<'GITCONFIG'
[user]
	email = previous@example.com
[credential]
	helper = osxkeychain
GITCONFIG
  before=$(cat "$sb/home/.gitconfig")
  status=$(run_bootstrap "$sb" repo "$(identity_input '' 'Ada Lovelace' 'ada@example.com')")

  [ "$status" = 0 ] || fail "bootstrap failed against a shadowing ~/.gitconfig: $(sandbox_out "$sb")"
  assert_contains "$(sandbox_out "$sb")" "git currently resolves user.email to \"previous@example.com\" from $sb/home/.gitconfig" \
    "bootstrap did not report the file git reads the email from"
  # user.name is set nowhere else, so nothing competes with the one just written.
  assert_not_contains "$(sandbox_out "$sb")" "resolves user.name" \
    "bootstrap reported a competing name that no file was setting"
  [ "$(cat "$sb/home/.gitconfig")" = "$before" ] \
    || fail "bootstrap modified ~/.gitconfig instead of only reporting it"
  [ "$(gitconfig_local_value "$sb" user.email)" = "ada@example.com" ] \
    || fail "the new email did not reach ~/.gitconfig.local"

  pass "identity: a ~/.gitconfig setting the same key is named, not edited"
}

# Nix is installed and flake.nix rewritten by now, so git refusing to touch a
# hand-broken ~/.gitconfig.local must cost a warning, not the whole switch.
test_identity_unparsable_gitconfig_local_still_switches() {
  local sb status
  sb=$(make_sandbox)
  printf '[user\n\tname = Broken\n' >"$sb/home/.gitconfig.local"
  status=$(run_bootstrap "$sb" repo "$(identity_input '' 'Ada Lovelace' 'ada@example.com')")

  [ "$status" = 0 ] || fail "an unparsable ~/.gitconfig.local aborted bootstrap: $(sandbox_out "$sb")"
  assert_contains "$(sandbox_calls "$sb")" "switch --flake $sb/home/.dotfiles#mac" \
    "bootstrap never reached the switch with an unparsable ~/.gitconfig.local"
  assert_contains "$(sandbox_out "$sb")" "git cannot parse ~/.gitconfig.local" \
    "bootstrap did not say the file could not be parsed"
  assert_contains "$(sandbox_out "$sb")" "git refused to write user.name and user.email to ~/.gitconfig.local" \
    "bootstrap did not report the writes it could not make"
  assert_not_contains "$(sandbox_out "$sb")" "holds no user.name and no user.email" \
    "bootstrap claimed an unparsable file simply holds nothing"

  pass "identity: an unparsable ~/.gitconfig.local warns and still reaches the switch"
}

# The prompt default comes from ~/.gitconfig.local alone. Anything wider would
# re-propose whoever configured this machine before - the exact misattribution
# taking the identity out of the tracked config is meant to end.
test_identity_offers_no_default_from_global_config() {
  local sb status
  sb=$(make_sandbox)
  cat >"$sb/home/.gitconfig" <<'GITCONFIG'
[user]
	name = Previous Owner
	email = previous@example.com
GITCONFIG
  status=$(run_bootstrap "$sb" repo "$(identity_input '' '' '')")

  [ "$status" = 0 ] || fail "bootstrap failed with no ~/.gitconfig.local: $(sandbox_out "$sb")"
  # The tilde is part of the message bootstrap prints, not a path to expand.
  # shellcheck disable=SC2088
  assert_contains "$(sandbox_out "$sb")" "~/.gitconfig.local holds no user.name and no user.email" \
    "bootstrap claimed an identity that ~/.gitconfig.local does not hold"
  assert_not_contains "$(sandbox_out "$sb")" "currently commits as" \
    "bootstrap proposed an identity from outside ~/.gitconfig.local"
  # ~/.gitconfig.local holds nothing, so nothing there disagrees with ~/.gitconfig.
  # Reporting a conflict here would advise unsetting the only identity present.
  assert_not_contains "$(sandbox_out "$sb")" "Previous Owner" \
    "bootstrap reported a conflict with an identity ~/.gitconfig.local does not hold"
  assert_not_contains "$(sandbox_out "$sb")" "Heads up" \
    "bootstrap reported a conflict when ~/.gitconfig.local holds nothing to conflict with"
  [ -z "$(gitconfig_local_value "$sb" user.name)" ] \
    || fail "empty input copied another identity into ~/.gitconfig.local"
  [ -z "$(gitconfig_local_value "$sb" user.email)" ] \
    || fail "empty input copied another identity into ~/.gitconfig.local"

  pass "identity: no default is taken from outside ~/.gitconfig.local"
}

test_link_created_when_absent
test_link_rerun_is_idempotent
test_link_replaces_stale_symlink
test_link_when_repo_already_is_dotfiles
test_link_refuses_unrelated_directory
test_link_refuses_regular_file
test_rebuild_refuses_unrelated_directory
test_rebuild_when_repo_already_is_dotfiles
test_username_match_leaves_flake_alone
test_username_mismatch_accepted_rewrites_flake
test_username_mismatch_declined_aborts
test_machine_name_valid_is_written
test_machine_name_invalid_aborts
test_machine_name_empty_keeps_default
test_identity_written_to_gitconfig_local
test_identity_empty_keeps_existing
test_identity_preserves_unrelated_gitconfig_local
test_identity_malformed_email_is_taken_as_typed
test_identity_name_without_email_is_kept
test_identity_half_set_file_is_reported_key_by_key
test_identity_competing_gitconfig_is_reported
test_identity_unparsable_gitconfig_local_still_switches
test_identity_offers_no_default_from_global_config

test_summary
