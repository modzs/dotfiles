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
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
