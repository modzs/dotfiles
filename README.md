# dotfiles

My personal development environment setup for macOS, managed with Nix via nix-darwin.
One repo, one command, and a fresh Mac ends up configured the same way every time.

## Contributing / Using This Repo

These are my personal dotfiles, shared publicly so people can read them, learn from them, and fork them freely.
Feature requests and pull requests are not accepted here, and PRs are auto-closed.
If you find a bug, please open a GitHub Issue using the bug report template.

## What you get

Running the switch builds:

- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Node, Hack Nerd Font)
- Agent CLIs from npm (`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi`), pinned and installed into `~/.npm-global`
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (WezTerm config with the rose-pine moon theme and dimmed unfocused windows)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Optional Pi theme and local extensions, generic UI settings and model overrides
- macOS system settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)

## Prerequisites

- macOS. This repo is macOS-only; it has no Linux or WSL configuration.
- Apple Silicon Mac, by default.
- Intel Mac: change one line in `configuration-darwin.nix`, set `nixpkgs.hostPlatform = "x86_64-darwin";`
- Network access on the first switch, and on any switch that changes a pinned npm CLI version. See "Agent toolchain" below.
- `no-mistakes` is the one tool this repo does not install for you. It is a one-time manual step, documented under "Agent toolchain".

## Employer provided machines ONLY

- Clone repo as normal
- Create untracked .local files directly into home directory
- Create `~/.gitconfig.local`
```sh
[user]
    name = Your Work Name
    email = your_work_email@company.com
```
- Create `~/.zshrc.local`
```sh
# Work-specific environment variables and aliases
export CORPORATE_PROXY="http://proxy.company.internal:8080"
alias workvpn="openvpn --config ~/work.ovpn"
```
Running `git status` inside your dotfiles folder ignores these `.local` files entirely. You can freely pull shared updates with `git pull` without merge conflicts or leaking work data.

Both hooks are already wired into `home.nix`, so creating the files is all you need to do:

- `programs.zsh.initContent` sources `~/.zshrc.local` if it exists.
- `programs.git.includes` pulls in `~/.gitconfig.local`.

**Which git identity wins:** `home.nix` sets no name or email of its own - it only pulls in `~/.gitconfig.local` through `programs.git.includes`. So the identity in that file is the identity you commit with, whether `bootstrap.sh` wrote it for you or you wrote a work one there yourself.

## Why It Won't Disrupt Anything

- Missing Files Are Safely Ignored:

The `[[ -f ~/.zshrc.local ]]` guard in `programs.zsh.initContent` checks that the file exists before sourcing it, so a personal machine without `.zshrc.local` skips it silently without errors.
Git ignores a missing `include.path` target automatically, so `programs.git.includes` is equally harmless when `~/.gitconfig.local` isn't there.

- Your Day-to-Day Workflow Stays Identical:

You continue staging, committing, and pushing exactly as you do now (`git add .`, `git commit`, `git push`).
The added `.gitignore` rules only ensure that any future `.local` files remain private to the machine where they were created.



## Fresh-machine setup

On a brand new machine, from a bare clone of this repo:

```sh
git clone https://github.com/modzs/dotfiles.git
cd dotfiles
```

Before you run it: review "Make it yours" below and adjust settings as needed.
`bootstrap.sh` applies the config to your machine, so do this first:

```sh
./bootstrap.sh
```

`bootstrap.sh` does six things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
3. Checks the `user` configured in `flake.nix` against your actual username, and offers to fix it if they differ.
4. Prompts for the machine name and writes it to the `hostName` line in `flake.nix`. Press Enter to keep the configured name.
5. Prompts for the git name and email you commit with and writes them to `~/.gitconfig.local`, outside this repo. Press Enter to keep the identity you already have.
6. Runs the first build and switch with `darwin-rebuild switch --flake ~/.dotfiles#mac`.

Before any of that it checks `~/.dotfiles`. If something is already there that
isn't a symlink and isn't this repo, it stops immediately rather than after
installing Nix and taking your password. Cloning the repo to `~/.dotfiles`
itself is fine - step 2 then has nothing to do.

After that, the config is applied and you're on the normal workflow below.

### Validate without applying

Once Nix is installed, you can check that the config builds without applying it (handy after edits):

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

That's it.
No separate build-and-copy step.

## Make it yours

This repo is mine. If you clone it, review these before you run `bootstrap.sh`:

- **Username**: `bootstrap.sh` detects your username and offers to set it, OR manually change the `user = "john"` line in `flake.nix`.
  Everything else (`configuration-darwin.nix`, `home.nix`, home directory paths) is threaded from that one variable.

- **Machine name**: `bootstrap.sh` prompts for it, OR manually change the `hostName = "mac";` line in `flake.nix`.
  nix-darwin applies it to `HostName`, `LocalHostName`, and `ComputerName` on every switch.
  The flake output name (`mac`) is a stable config identifier and doesn't follow the machine name.

- **Git identity**: `bootstrap.sh` prompts for the name and email your commits carry and writes them to `~/.gitconfig.local`.
  Nothing in this repo sets an identity, so until that file exists git has none to use.

- **Homebrew packages and system settings:** edit `configuration-darwin.nix`:
  - the `brews` and `casks` arrays
  - `system.defaults` for macOS settings (dark mode, key repeat, etc.)
  - If you have existing Homebrew packages not in the list, they will be removed on first switch (see Homebrew cleanup warning below)

- **CPU architecture:** If you're on Intel Mac, change one line in `configuration-darwin.nix`:
  `nixpkgs.hostPlatform = "x86_64-darwin";`

**Homebrew cleanup warning:** `configuration-darwin.nix` sets `homebrew.onActivation.cleanup = "zap"`.
This means every switch removes any Homebrew package or cask not listed in the `brews` and `casks` arrays.
Read through these arrays before running `bootstrap.sh` for the first time, and add anything you want to keep.

**Heads-up:**

- `home/AGENTS.md` is my personal agent policy, and `home.nix` installs it for Claude, Codex, and opencode.
  If you clone this repo, you'd silently inherit my agent instructions - edit or delete `home/AGENTS.md` if you don't want that.
- The `cc` and `co` shell aliases in `home.nix` are high-agency shortcuts: `claude --dangerously-skip-permissions` and `codex --full-auto`.
  They're convenient for me, but know what they do before you use them.
- `home/.claude/settings.json` registers `SessionStart` hooks that run `gh-axi`, `chrome-devtools-axi`, and `lavish-axi` on every Claude Code session.
  Those three tools generate that block themselves via `<tool> setup hooks`; it is committed here so a fresh machine gets it without running anything.
  Delete the `hooks` key if you don't want them.
- Home Manager prepends `~/.npm-global/bin` and `~/.no-mistakes/bin` to `PATH`, so anything you install there shadows a same-named Homebrew binary.

## Repo tour

- `flake.nix` - the entry point. Declares the single `mac` nix-darwin configuration.
- `configuration-darwin.nix` - system-level config: macOS defaults, Homebrew.
- `home.nix` - user-level config: shell, packages, prompt, symlinks, and the pinned npm agent CLIs.
- `bootstrap.sh` - one-time setup: installs Nix, symlinks the repo, checks username, sets the machine name and git identity, and runs the first build.
- `rebuild.sh` - applies changes after the first switch, with `darwin-rebuild switch`.
- `lib/` - shell helpers shared by the setup scripts and the `home.nix` activation.
- `home/` - the actual config files that get symlinked into place.
- `tests/` - the behaviour tests. Run them with `./tests/run.sh`, or
  `./tests/run.sh --strict` to fail on any check that had to be skipped.
  CI runs the strict form on every pull request, along with `nix flake check`,
  a full build of the system closure, and a shellcheck lint of the shell scripts.

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`home.nix` uses `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` straight at `home/.config/nvim` in this repo, so the two never drift out of sync.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list.

## Agent toolchain

Six command-line agent tools live on this machine: Node plus five npm CLIs (`gh-axi`,
`chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi`), and `no-mistakes`.
All of them are declared here, because `homebrew.onActivation.cleanup = "zap"` deletes any
Homebrew package this repo doesn't list, and Node installed through Homebrew would take the
npm globals underneath it down with it.

**Node comes from nixpkgs, not Homebrew.** `home.nix` lists `nodejs_26` in `home.packages`,
so the version is pinned by `flake.lock` and the zap can never reach it. That choice has a
second effect worth knowing about: a Nix-provided node's default `npm prefix -g` is its own
read-only store path, so this config sets `NPM_CONFIG_PREFIX=~/.npm-global` instead. Global
npm packages therefore land in your home directory rather than in `/opt/homebrew`, which is
what puts them permanently out of the zap's reach. Nothing about `cleanup = "zap"` is
weakened; the toolchain simply stops living in the tree it manages.

**The five npm CLIs are pinned.** They aren't in nixpkgs, so a Home Manager activation step in
`home.nix` installs each one at an exact version into `~/.npm-global`. The versions are the
`npmGlobals` attribute set in `home.nix`; to move one, edit the version and run `./rebuild.sh`.
Pinning is deliberate. Unpinned, a routine rebuild could silently change a tool's behaviour
underneath you; pinned, the version only moves when you change this file and commit it.

The step is version-guarded, so a rebuild with nothing to change reads five `package.json`
files and makes no network calls. If an install does fail, for example on a machine with no
network, it prints a warning and the switch continues rather than aborting.

**`no-mistakes` is a documented manual step, not a declared one.** Its installer always fetches
the latest release rather than a version you choose, and it restarts the `no-mistakes` daemon
as its last act. Neither belongs in an unattended `darwin-rebuild switch`, so this repo does
not run it. What the repo does do is put `~/.no-mistakes/bin` on `PATH`, which is where the
installer's binary lives, so once installed it survives every rebuild untouched. Install it
once per machine:

```sh
NO_MISTAKES_LINK_DIR="$HOME/.no-mistakes/bin" \
  curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
```

Setting `NO_MISTAKES_LINK_DIR` to the install directory makes the installer skip its symlink
step, which is the only part that wanted `sudo`. `PATH` already covers it.

### `NODE_EXTRA_CA_CERTS`

`home.nix` sets `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt`, the CA bundle
nix-darwin already manages through `security.pki.installCACerts`.

The Nix node doesn't need this: its OpenSSL finds that bundle on its own. It is here for every
*other* Node on the machine. A Homebrew-built node links Homebrew's `openssl@3` and looks for
roots in `/opt/homebrew/etc/openssl@3`, which on this machine is empty, so every HTTPS request
from such a node fails with `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` and no `npm install` can
succeed. One declared variable removes that whole class of failure for any Node that turns up,
whether from a cask, a project toolchain, or a later `brew install node`.

### Migrating a machine that already had Homebrew Node

If Node and the npm CLIs were installed through Homebrew before this change, the first
`./rebuild.sh` zaps Homebrew's `node` and installs everything into `~/.npm-global`. Because
Home Manager prepends `~/.npm-global/bin` to `PATH`, the new copies win immediately and
nothing is broken. The old files are simply left behind. Clear them out once:

```sh
rm -rf /opt/homebrew/lib/node_modules/{gh-axi,chrome-devtools-axi,lavish-axi,tasks-axi,quota-axi}
rm -f /opt/homebrew/bin/{gh-axi,chrome-devtools-axi,lavish-axi,tasks-axi,quota-axi,no-mistakes}
```

The last of those is a `no-mistakes` symlink that used to live inside Homebrew's tree.
`~/.no-mistakes/bin` on `PATH` replaces it.

## Optional Pi configuration

Pi is an opt-in CLI, not a dependency this repository vendors. Install it from its owner with the [official Pi instructions](https://pi.dev), for example:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

[Pi Launcher](https://github.com/kunchenguid/homebrew-tap) is also optional and installed from its owner, not declared by this config:

```sh
brew install --cask kunchenguid/tap/pi-launcher
```

Home Manager owns exactly two repository-authored Pi directories: `~/.pi/agent/themes` and `~/.pi/agent/extensions`. It also links `models.json` and `settings.json` as individual files. The local extension directory is for public, repository-authored extensions only - third-party package code never belongs there. Run `/reload` after editing a local extension or other Pi resources. The terminal-title extension shows a spinner while Pi is working, then a completion mark with the session name or current directory. The `rose-pine-moon` theme was authored clean-room from the public [Rosé Pine Moon palette](https://rosepinetheme.com/palette) and Pi's [public theme schema](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json), not from a private or live theme file.

### Pi Calm

`home/.pi/agent/extensions/calm` is a standalone local Pi extension. Home Manager's existing global extensions-directory link makes Pi auto-load it without another declaration. `/calm` toggles a conversation-only presentation mode and is off by default. Its choice is stored locally in `~/.pi/agent/calm` (or the directory selected by `PI_CODING_AGENT_DIR`), not in this repository or Home Manager. Adapted from Firstmate under the bundled MIT license, Calm imports no Firstmate modules and has no Firstmate runtime dependency.

When enabled, Calm hides collapsed thinking and the call/result shells for Pi's seven built-in tools (`read`, `bash`, `edit`, `write`, `grep`, `find`, and `ls`) without leaving blank transcript rows. During an active run it replaces Pi's working row with a two-line animated blue-water, yellow-boat widget. `/calm` restores Pi's stock rendering and preserves the existing Ctrl+O tool-expansion choice.

Calm never changes prompts, tool execution, model context, session data, or ordering. `/share` and `/export` use the complete stock transcript. Generic custom tools, images, and unsupported Pi transcript classes deliberately remain visible because Pi has no safe general-purpose transcript filter. If a future Pi release no longer exports the exact collapsed-thinking rendering seam, Calm logs one diagnostic and leaves only that adapter disabled; all other behavior remains available.

Pi's package system declares two third-party sources in the linked global `settings.json`:

- `npm:pi-web-access@0.14.0` - the exact public npm release for web access.
- `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` - the exact public npm release from `ryan_nookpi`.

The versions are immutable pins, so Pi does not move them during package updates. Deliberate updates require a new source and security audit, followed by an explicit pin change in `home/.pi/agent/settings.json`. On Pi 0.82.0, global settings declarations install missing pinned packages automatically at startup. No one-time install command is required. Pi keeps the downloaded npm package trees in its own unmanaged `~/.pi/agent/npm` runtime directory, outside Home Manager and Git tracking.

Both packages execute with your full user permissions and must be trusted like any other executable code.

Home Manager deliberately does not manage `~/.pi/agent` itself, or Pi authentication, sessions, trust decisions, caches, npm package trees, or any other runtime state. The model overrides contain no credentials or endpoint settings, do not choose a default model, and only take effect after you authenticate Pi yourself. This remains an additive post-video layer: it does not install Pi, a launcher, or package source code into this repository.

## Notes

The first time you launch `nvim`, it bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim) by cloning plugins from GitHub.
That needs network access once; after that it's offline.
Neovim and WezTerm both use the rose-pine moon theme.
Neovim keeps italics off and uses a transparent background so it matches the terminal setup.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.
