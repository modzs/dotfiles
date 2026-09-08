# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "zap"` in `configuration-darwin.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- `bootstrap.sh` and `rebuild.sh` must stay bash 3.2 compatible: macOS ships bash 3.2 as `/bin/bash`, and
  `#!/usr/bin/env bash` does not change that on a stock Mac. No associative arrays, `mapfile`/`readarray`,
  `${var^^}`/`${var,,}`, `&>>`, `[[ -v ]]`, or `${!var@}`. They also use BSD `sed -i '' -E`, which GNU sed rejects.
- Node is deliberately provided by nixpkgs (`home.packages`), NOT by Homebrew `brews`. That is
  what moves `npm prefix -g` to `~/.npm-global` and puts the npm agent CLIs outside the tree
  `cleanup = "zap"` manages. Adding `node` to `brews` would silently undo the fix. See the
  "Agent toolchain" section of README.md.
- The three axi tools generate their Claude `SessionStart` hooks with `<tool> setup hooks`,
  which writes to `~/.claude/settings.json` - a `mkOutOfStoreSymlink` to the tracked
  `home/.claude/settings.json`. Running it dirties the working tree, so the hooks are committed
  instead of regenerated during activation.
- The `~/.dotfiles` link logic lives once, in `lib/dotfiles-link.sh`, and is sourced by both
  `bootstrap.sh` and `rebuild.sh`. Do not re-inline `ln -sfn "$DIR" ~/.dotfiles` in either script:
  that form silently links *into* an existing real `~/.dotfiles` directory and exits 0.
- The npm agent-CLI install step lives in `lib/npm-globals.sh`, not inlined in `home.nix`, so
  `tests/npm-globals.test.sh` can execute it. `home.nix` passes the pins in as arguments;
  `npmGlobals` there stays the single source of truth. Do not re-inline it into the activation
  string, and do not hardcode versions in the script.
- The git identity is deliberately absent from `home.nix`: this is a public repo people fork, so an
  identity there would follow every clone. `bootstrap.sh` step 5 prompts for it and writes it to the
  untracked `~/.gitconfig.local`, which `programs.git.includes` pulls in. Do not add
  `programs.git.settings.user` back, and never commit `~/.gitconfig.local`.
- The git identity report lives once, in `lib/git-identity.sh`, and both `bootstrap.sh` and
  `rebuild.sh` call it only AFTER the switch: the switch is what installs `programs.git.includes`,
  so an earlier answer describes a machine that no longer exists. It reports the value and origin
  `git config --show-origin` names, never a claim about how git ranks config files, and never a
  remedy for a key that some file already sets. The mode argument is the whole difference between
  the two callers: `bootstrap.sh` passes `full` and runs once, so it also names the file behind an
  identity resolving from somewhere other than `~/.gitconfig.local`; `rebuild.sh` passes
  `missing-only` and runs on every switch, so it speaks only about a key git resolves to nothing.
  Keep that split in the one function - duplicating it into the two scripts is the drift this file
  exists to prevent. `rebuild.sh` therefore cannot go back to `exec sudo`; it keeps and re-raises
  the switch's exit status.
- Tests live in `tests/` and run with `./tests/run.sh` (`--strict` fails on any skipped check).
  A check that could not run must report `skip -`, never `ok -`; CI runs the strict form, so a
  new environment-dependent test needs its dependency added to `.github/workflows/ci.yml`.
- The `nixpkgs` input in `flake.nix` tracks `nixpkgs-26.05-darwin`, not `release-26.05`. The
  darwin branch only advances to commits whose Darwin jobset finished building, so the binary
  cache is reliable and `./rebuild.sh` does not fall back to compiling from source. It lags the
  release branch by design; do not "modernize" it back to the generic branch.
  `tests/nixpkgs-channel.test.sh` guards this by asking channels.nixos.org and cache.nixos.org.
- The `model` in `home/.claude/settings.json` is the repo owner's deliberate default for every
  Claude Code session on the machine. Keep the short alias form (a dated model id rots); do not
  drop the key to fall back to the account default. A first session on a 1M-context account
  rewrites the alias to `"opus[1m]"` in place once - expected, one-time, and still Opus - but do
  not commit that value: the bracketed form encodes an account entitlement, not a repo choice.
- `skipDangerousModePermissionPrompt: true` in the same file is intentional: this machine runs
  agents unattended, and the startup prompt would block them. Do not remove it as a "hardening" fix.
- herdr writes a `SessionStart` hook into `home/.claude/settings.json` (absolute
  `/Users/<name>/.claude/hooks/herdr-agent-state.sh`) when its Claude integration is installed or
  updated. Expected, machine-local, and never committed - the path is one machine's home and the
  script is not in this repo. The remedy is `git checkout -- home/.claude/settings.json`;
  `tests/repo-hygiene.test.sh` fails on any absolute `/Users/` path in that file.
- Do NOT stop that write with `herdr integration uninstall claude`. Firstmate classifies worker
  state from herdr's native agent state, which that hook is the source of, so uninstalling trades
  a rare cosmetic diff for firstmate no longer telling a working crewmate from a dead one. There
  is no cleaner mechanism: Claude Code has exactly one user-scope settings file (no
  `~/.claude/settings.local.json`), and herdr only ever writes there.
- `onboarding = false` in `home/.config/herdr/config.toml` is a real preference, not stray runtime
  state: herdr appends that key the first time onboarding is dismissed, and `~/.config/herdr` is an
  out-of-store symlink, so an undeclared key lands as an unexplained diff. Declaring it leaves herdr
  nothing to write. `tests/repo-hygiene.test.sh` guards it with a real TOML parser, which is why the
  CI test job pins python3.
- A procedure must not be stated in two documents: one owns it, and the other keeps the context
  and the warnings and cross-references the owner instead of repeating the steps - a duplicated
  recipe is how a bug once got fixed in one copy and missed in the other. Where a procedure could
  sensibly live in either, HOW-TO.md owns step-by-step commands and troubleshooting and README.md
  owns architecture, rationale and orientation; naming a command in a sentence is not a recipe.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
