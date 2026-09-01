# dotfiles

My personal development environment setup, managed with Nix.
Supports both macOS (via nix-darwin) and Arch Linux / Omarchy (via home-manager).
One repo, one command, and a fresh machine ends up configured the same way every time.

## Contributing / Using This Repo

These are my personal dotfiles, shared publicly so people can read them, learn from them, and fork them freely.
Feature requests and pull requests are not accepted here, and PRs are auto-closed.
If you find a bug, please open a GitHub Issue using the bug report template.

## What you get

Running the switch builds:

**All platforms:**
- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (WezTerm config with the rose-pine moon theme and dimmed unfocused windows)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Optional Pi theme and local extensions, generic UI settings and model overrides

**macOS only:**
- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)

## Prerequisites

**macOS:**
- Apple Silicon Mac, by default.
- Intel Mac: change one line in `configuration-darwin.nix`, set `nixpkgs.hostPlatform = "x86_64-darwin";`

**Omarchy / Arch Linux:**
- A working Omarchy installation
- x86_64 system (use `uname -m` to verify)

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
Running git status inside your dotfiles folder will ignore these .local files entirely . You can freely pull shared updates using git pull without facing merge conflicts or leaking work data .

## Why It Won't Disrupt Anything

- Missing Files Are Safely Ignored:

In `.zshrc`, the guard condition `[[ -f ~/.zshrc.local ]]` checks if the file exists first. If you do not have `.zshrc.local` on your personal machine, the shell skips it silently without errors.
In `.gitconfig`, the `[include]` directive is designed by Git to ignore missing target files automatically.

- Your Day-to-Day Workflow Stays Identical:

You continue staging, committing, and pushing exactly as you do now (`git add .`, `git commit`, `git push`).
The added `.gitignore` rules only ensure that any future `.local` files remain private to the machine where they were created .



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

`bootstrap.sh` does five things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
3. Checks the `user` configured in `flake.nix` against your actual username, and offers to fix it if they differ.
4. Prompts for the machine name and writes it to the `hostName` line in `flake.nix`. Press Enter to keep the configured name.
5. Runs the first build and switch:
   - On macOS: runs `darwin-rebuild switch` via nix-darwin
   - On Omarchy/Linux: runs `home-manager switch` via home-manager

After that, the config is applied and you're on the normal workflow below.

### Validate without applying

Once Nix is installed, you can check that the config builds without applying it (handy after edits):

**macOS:**
```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

**Omarchy/Linux:**
```sh
nix flake check --no-build
nix build .#homeConfigurations.omarchy.activationPackage --dry-run
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
  On macOS, nix-darwin applies it to `HostName`, `LocalHostName`, and `ComputerName` on every switch.
  On Omarchy/Linux, `bootstrap.sh` applies it with `hostnamectl` (home-manager is user-level and can't set it).
  The flake output names (`mac`, `omarchy`) are stable config identifiers and don't follow the machine name.

- **macOS setup:** If you're on macOS and want to customize Homebrew packages or system settings:
  - Edit `configuration-darwin.nix`: the `brews` and `casks` arrays
  - Edit `configuration-darwin.nix`: `system.defaults` for macOS settings (dark mode, key repeat, etc.)
  - If you have existing Homebrew packages not in the list, they will be removed on first switch (see Homebrew cleanup warning below)

- **Omarchy/Linux setup:** This uses home-manager only. System packages are managed via pacman or AUR outside of this repo.

- **CPU architecture:** If you're on Intel Mac, change one line in `configuration-darwin.nix`:
  `nixpkgs.hostPlatform = "x86_64-darwin";`

**Git identity:** This config does not set your git name or email (it's in `home.nix` but you should customize it).
Edit the `programs.git.settings.user` section in `home.nix` with your own identity, or Git will prompt you on your first commit.

**Homebrew cleanup warning (macOS only):** `configuration-darwin.nix` sets `homebrew.onActivation.cleanup = "zap"`.
This means every switch removes any Homebrew package or cask not listed in the `brews` and `casks` arrays.
Read through these arrays before running `bootstrap.sh` for the first time, and add anything you want to keep.

**Heads-up:**

- `home/AGENTS.md` is my personal agent policy, and `home.nix` installs it for Claude, Codex, and opencode.
  If you clone this repo, you'd silently inherit my agent instructions - edit or delete `home/AGENTS.md` if you don't want that.
- The `cc` and `co` shell aliases in `home.nix` are high-agency shortcuts: `claude --dangerously-skip-permissions` and `codex --full-auto`.
  They're convenient for me, but know what they do before you use them.

## Repo tour

- `flake.nix` - the entry point. Declares both the `mac` (macOS) and `omarchy` (Arch Linux) configurations.
- `configuration-darwin.nix` - macOS-only, system-level config: system defaults, Homebrew.
- `home.nix` - user-level config (both platforms): shell, packages, prompt, and symlinks. Platform-aware via `isDarwin` flag.
- `bootstrap.sh` - one-time setup: installs Nix, symlinks the repo, checks username, sets the machine name, and runs the first build.
- `rebuild.sh` - applies changes after the first switch. Platform-aware: uses `darwin-rebuild` on macOS, `home-manager` on Linux.
- `home/` - the actual config files that get symlinked into place.

## System packages on Omarchy / Linux

This repo uses home-manager only, which means it manages user-level packages and config.
System-level packages (kernel modules, system services, etc.) are managed outside of this repo via Omarchy's pacman and AUR.

Common development tools (git, zsh, neovim, etc.) are included in `home.nix` and will be installed via Nix for your user.
If you need additional system packages, install them with pacman or AUR as you normally would on Omarchy.

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`home.nix` uses `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` straight at `home/.config/nvim` in this repo, so the two never drift out of sync.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list.

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

- `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` - the exact public npm release from `ryan_nookpi`.
- `git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055` - the exact public `algal` commit for experimental OpenAI server-side compaction.

The version and commit are immutable pins, so Pi does not move them during package updates. Deliberate updates require a new source and security audit, followed by an explicit pin change in `home/.pi/agent/settings.json`. On Pi 0.82.0, global settings declarations install missing pinned packages automatically at startup. No one-time install command is required. Pi keeps the downloaded npm and git package trees in its own unmanaged `~/.pi/agent/npm` and `~/.pi/agent/git` runtime directories, outside Home Manager and Git tracking.

Both packages execute with your full user permissions and must be trusted like any other executable code. The compaction package is experimental, sends the relevant OpenAI compaction and continuity data to OpenAI, and upstream declares the stale peer range `>=0.80.9 <0.81.0`; this exact immutable ref was locally proven to load and perform remote compaction on Pi 0.82.0. Do not treat that proof as a guarantee for a different Pi version or a different package ref.

Home Manager deliberately does not manage `~/.pi/agent` itself, or Pi authentication, sessions, trust decisions, caches, npm/git package trees, or any other runtime state. The model overrides contain no credentials or endpoint settings, do not choose a default model, and only take effect after you authenticate Pi yourself. This remains an additive post-video layer: it does not install Pi, a launcher, or package source code into this repository.

## Notes

The first time you launch `nvim`, it bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim) by cloning plugins from GitHub.
That needs network access once; after that it's offline.
Neovim and WezTerm both use the rose-pine moon theme.
Neovim keeps italics off and uses a transparent background on macOS, Windows, and WSL so it matches the terminal setup.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.
