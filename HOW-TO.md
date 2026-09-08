# How to Use These Dotfiles

This guide walks you through setting up your development environment using this dotfiles repo on macOS. This repo is macOS-only.

## Table of Contents

1. [macOS Setup](#macos-setup)
2. [Daily Workflow](#daily-workflow)
3. [Customizing Your Setup](#customizing-your-setup)
4. [Troubleshooting](#troubleshooting)
5. [Summary](#summary)
6. [Quick Reference: What's Where](#quick-reference-whats-where)

---

## macOS Setup

### Step 1: Clone the Repository

```bash
git clone https://github.com/modzs/dotfiles.git
cd dotfiles
```

**What it does:**
- Downloads your dotfiles repo from GitHub into a new `dotfiles` directory
- Changes into that directory so you can run the setup scripts

### Step 2: Review Configuration Before Running

Before you proceed, edit `flake.nix` if needed:

```bash
nano flake.nix
```

Look for this line and update if your macOS username isn't `john`:
```nix
user = "john";
```

And this line, if you want a different machine name (bootstrap will also prompt you for it):
```nix
hostName = "mac";
```

Also check `configuration-darwin.nix` for:
- **Homebrew packages:** Edit the `brews` array to add/remove CLI tools
- **Homebrew casks:** Edit the `casks` array to add/remove GUI apps
- **System settings:** Customize macOS defaults like dark mode, key repeat speed, etc.

**What these do:**
- `flake.nix`: Declares your system configuration entry point
- `configuration-darwin.nix`: Contains all macOS-specific system settings and package lists
- Both files are read during the initial setup

### Step 3: Run Bootstrap Script

```bash
./bootstrap.sh
```

**What it does (step by step):**

1. **Installs Determinate Nix** (if not already installed)
   - Downloads and runs the Nix installer
   - Creates `/nix` directory for Nix packages
   
2. **Symlinks the repo to `~/.dotfiles`**
   - Creates a shortcut from your home directory to this repo
   - Allows your config files to be edited in place without rebuilding
   
3. **Checks and fixes username**
   - Compares the `user = "john"` in `flake.nix` with your actual macOS username
   - Offers to update it automatically if they don't match

4. **Prompts for the machine name**
   - Shows the current machine name and the `hostName = "mac"` value in `flake.nix`
   - Press Enter to keep the configured name, or type a new one to rewrite that line
   - nix-darwin applies it to `HostName`, `LocalHostName`, and `ComputerName` during the switch

5. **Prompts for the git identity**
   - Shows which of `user.name` and `user.email` `~/.gitconfig.local` currently holds
   - Press Enter to keep what that file already says, or type a name and an email to write them
   - The identity goes to `~/.gitconfig.local`, outside this repo, never into the tracked config

6. **Runs the first build**
   - Executes `darwin-rebuild switch` to apply your configuration
   - Installs packages, configures system settings, creates symlinks
   - This takes 5-15 minutes depending on your internet and machine

**Expected output:**
- You'll see lots of download/build progress text
- At the end: "==> Done. Use ./rebuild.sh for future changes."

### Step 4: Verify the Setup

After bootstrap completes, verify everything installed correctly:

```bash
echo $EDITOR
```

**Expected output:** `nvim`

Check that Neovim is available:

```bash
nvim --version
```

**Expected output:** Neovim version info (e.g., "NVIM v0.9.0")

Check that Node and the agent CLIs came from the right places:

```bash
which node
gh-axi --version
```

**Expected output:** a path under `/etc/profiles/per-user/` or `~/.nix-profile` for `node`
(not `/opt/homebrew/bin/node`), and the version pinned in `home.nix` for `gh-axi`.
If `which node` points into `/opt/homebrew`, a leftover Homebrew Node is shadowing the Nix
one; see "Migrating a machine that already had Homebrew Node" in README.md.

### Step 5: Verify the Git Identity

Nothing in this repo sets a git name or email. `bootstrap.sh` step 5 prompts for yours and writes it to the untracked `~/.gitconfig.local`, which `home.nix` pulls in through `programs.git.includes`. If you skipped that prompt, nothing in this config sets an identity.

Check what you actually have after the switch:

```bash
git config --show-origin --get user.name
git config --show-origin --get user.email
```

**Expected output:** your own name and email, coming from `~/.gitconfig.local`. Set them there - never in this repo - with the commands in [Setting the Git Identity](#setting-the-git-identity) below.

If the origin is some other file, that file is what you actually commit as. `~/.gitconfig` is the usual one on a machine that was used before this config, and `user.name` and `user.email` are resolved independently, so you can end up with a name from one file and an email from another. Remove the setting from the file git names - `git config --file ~/.gitconfig --unset user.email` - then run the command again to see where git reads that key from now.

---

## Daily Workflow

### Updating to the Latest Config

When changes land in the repo - yours from another machine, or anyone else's - this is how you
bring a machine up to date:

```bash
cd ~/.dotfiles
git pull
./rebuild.sh
```

`~/.dotfiles` is a symlink to wherever you cloned the repo, so this works the same from either
path: `cd ~/.dotfiles` and `cd ~/code/dotfiles` land you in the same working copy.

**If `git pull` refuses because the working copy is dirty**

git stops with `Your local changes to the following files would be overwritten by merge` when an
incoming commit touches a file you have uncommitted changes in. Look before you discard anything:

```bash
git status
git diff
```

Often it is not an edit you made. `home/.claude/settings.json` is tracked *and* linked into
`~/.claude`, and two tools write to it on your machine:

- herdr adds a `SessionStart` hook with your home directory spelled out in full, whenever its
  Claude integration is installed or updated.
- Claude Code rewrites `"model": "opus"` to `"opus[1m]"` once, on a 1M-context account.

Both are expected locally and wrong for everyone else, so neither is ever committed. Restore the
file and pull again:

```bash
git checkout -- home/.claude/settings.json
git pull
```

`git checkout --` throws the local change away, which is exactly why you read `git diff` first.
If the diff turns out to be an edit you wanted, commit it instead of discarding it. See
[`git status` Shows Changes You Never Made](#git-status-shows-changes-you-never-made) for the
longer version.

**Which pulled changes need `./rebuild.sh`**

Files under `home/` are symlinked into place, so a pull updates your live config the moment it
lands - no rebuild involved. Everything else - `home.nix`, `configuration-darwin.nix`,
`flake.nix`, `flake.lock`, package lists, macOS defaults, the pinned npm CLI versions - only
takes effect after the switch. See "How the symlinks work" in README.md for why. A rebuild that
had nothing to do is cheap and harmless, so when you are unsure, just run it.

**Check that the update applied**

```bash
git status -sb
git log --oneline -1
```

`## main...origin/main` with no `behind` count means the working copy now has everything from the
remote, and the log line names the commit you are on.

For the switch itself, look at the system profile:

```bash
ls -l /nix/var/nix/profiles/system
```

The timestamp on that symlink is when your last switch ran, and the `system-N-link` it points at
is the generation now active.

If the pull moved a pinned npm CLI, the installed copy should match the pin:

```bash
grep -A 6 "npmGlobals" ~/.dotfiles/home.nix
gh-axi --version
```

**The first pull after a long gap can take a while.** If `flake.lock` moved, the switch may
download or build a lot of packages before it finishes - minutes, not seconds. That is expected,
not a sign anything is wrong.

### Making Changes

Edit your config files directly in the repo. For example:

```bash
# Edit your Neovim config
nano ~/.dotfiles/home/.config/nvim/init.lua
```

**What it does:**
- Opens your Neovim config for editing
- Changes take effect immediately (no rebuild needed for config file changes)

Or edit shell aliases:

```bash
nano ~/.dotfiles/home.nix
```

Find the `shellAliases` section and add/modify as needed.

### Applying Changes

After editing config files that aren't symlinked (like `flake.nix`, `home.nix`, or package lists), rebuild:

```bash
cd ~/.dotfiles
./rebuild.sh
```

**What it does:**
- Re-runs `darwin-rebuild switch --flake ~/.dotfiles#mac` with your updated configuration
- Installs/removes packages based on changes
- Takes 1-5 minutes

### Checking What Will Change

Before applying, preview what will happen:

```bash
cd ~/.dotfiles
nix build .#darwinConfigurations.mac.system --dry-run
```

**What it does:**
- Builds your config without applying it
- Shows you what will be changed
- Useful for spotting mistakes before committing

---

## Customizing Your Setup

### Adding a New Package

Edit `home.nix`:

```bash
nano ~/.dotfiles/home.nix
```

Find the `home.packages` attribute and add your package:

```nix
home.packages = with pkgs; [
  # cli i use constantly
  ripgrep
  fd
  fzf
  jq
  lazygit
  neovim
  nerd-fonts.hack
  git        # <- add new package here
  htop       # <- and here
];
```

**What it does:**
- Declares that you want these packages available in your user environment
- `with pkgs;` allows you to reference packages by name without the `pkgs.` prefix

Then apply the change:

```bash
cd ~/.dotfiles
./rebuild.sh
```

To find available packages, search Nixpkgs:

```bash
nix search nixpkgs git
```

**What it does:**
- Searches for packages matching "git" in nixpkgs
- Shows available versions and descriptions

### Setting the Git Identity

The identity lives in `~/.gitconfig.local`, never in this repo:

```bash
git config --file ~/.gitconfig.local user.name "Your Name"
git config --file ~/.gitconfig.local user.email "your@email.com"
```

**What it does:**
- Sets your git name and email in the untracked `~/.gitconfig.local`
- Takes effect at once - `home.nix` already includes that file, so no rebuild is needed
- Keeps your identity out of a repo that gets cloned and forked

### Adding Shell Aliases

Edit `home.nix` and find the `programs.zsh.shellAliases` attribute:

```nix
shellAliases = {
  ".." = "cd ..";
  "add" = "git add .";
  "push" = "git push";
  "pull" = "git pull";
  "m" = "git switch main";
  "cc" = "claude --dangerously-skip-permissions";
  "co" = "codex --full-auto";
  "myalias" = "my command here";  # <- add new alias here
};
```

Then apply:

```bash
./rebuild.sh
```

**What it does:**
- Creates short commands that expand to longer ones
- `myalias` would run `my command here` when typed
- Available in your next shell session

### Adding Homebrew Packages

Edit `configuration-darwin.nix`:

```bash
nano ~/.dotfiles/configuration-darwin.nix
```

Find the `brews` section (CLI tools):

```nix
brews = [
  "herdr"
  "gh"
  "my-tool"  # <- add new brew here
];
```

Or find the `casks` section (GUI apps):

```nix
casks = [
  "wezterm"
  "claude-code"
  "ghostty"
  "my-app"  # <- add new cask here
];
```

Then apply:

```bash
./rebuild.sh
```

**What it does:**
- Installs the specified Homebrew formula or cask
- Removes any packages not in the list (because `cleanup = "zap"` is enabled)
- Takes a few minutes

### Bumping or Adding a Pinned npm Agent CLI

The agent CLIs (`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi`) are not
in Nixpkgs, so `home.nix` pins them by version and installs them into `~/.npm-global`.

Edit `home.nix` and find the `npmGlobals` attribute set near the top. It maps a package name to
an exact version, one line each:

```nix
npmGlobals = {
  "gh-axi" = "<version>";        # <- edit a version in place to bump a pin
  "some-other-cli" = "1.2.3";    # <- add a line to add a new CLI
};
```

The versions in the file are the live pins - read them there rather than from this guide.

Check what versions are available first:

```bash
npm view gh-axi versions --json | tail -20
```

Then apply:

```bash
cd ~/.dotfiles
./rebuild.sh
```

**What it does:**
- Compares each pinned version against what is already in `~/.npm-global`
- Installs only the ones that differ, so an unchanged rebuild makes no network calls
- Leaves the existing copy in place and prints a warning if an install fails

Do NOT use `npm install -g` by hand to change one of these. The next `./rebuild.sh` will put
the pinned version back, which is the point of pinning. Change `home.nix` instead.

### Adding Work-Specific Configuration (Employer Machine)

If you're on a work machine and need separate config:

Set the work identity in `~/.gitconfig.local`:

```bash
git config --file ~/.gitconfig.local user.name "Work Name"
git config --file ~/.gitconfig.local user.email "work@company.com"
```

**What it does:**
- Sets the work identity in the local git config file, creating it if it isn't there
- Changes only those two keys, so anything else you keep in that file survives - unlike a `cat >` heredoc, which would replace the whole file
- `programs.git.includes` in `home.nix` pulls it in, and `home.nix` sets no identity of its own; `git config --show-origin --get user.email` names the file git actually reads the identity from
- Not tracked by git (stays private to your machine)

Similarly, create `~/.zshrc.local` for work-specific environment variables:

```bash
cat > ~/.zshrc.local <<'EOF'
export WORK_PROXY="http://proxy.company.local:8080"
alias workvpn="openvpn --config ~/work.ovpn"
EOF
```

**What it does:**
- Adds work-specific environment variables and aliases
- Sourced automatically by the `~/.zshrc` Home Manager generates from `programs.zsh.initContent`
- Not tracked by git

Both `.local` files are in `.gitignore` and won't be committed to the repo.

No further wiring is needed: `home.nix` already sources `~/.zshrc.local` from `programs.zsh.initContent` and pulls in `~/.gitconfig.local` through `programs.git.includes`. `home.nix` sets no name or email itself, so `~/.gitconfig.local` is where a work machine's identity goes, and git simply has none when neither that file nor a leftover `~/.gitconfig` supplies one.

---

## Troubleshooting

### Command Not Found After Bootstrap

If a newly installed package isn't found:

```bash
exec zsh
```

**What it does:**
- Reloads your shell session
- Makes newly installed packages available

### Want to Check What Will Be Installed First?

Validate without applying:

```bash
nix flake check --no-build
```

**What it does:**
- Checks your flake files for syntax errors
- Doesn't download or build anything
- Good for catching typos before committing

### Need to See Detailed Build Errors?

Add `--show-trace` for more details:

```bash
darwin-rebuild switch --flake ~/.dotfiles#mac --show-trace
```

**What it does:**
- Shows the full stack trace if something fails
- Helps identify where the error occurred

### Git Says "Path Not Tracked"

If you get an error about files not being tracked by Git during a build:

```bash
git add configuration-darwin.nix home.nix
git status
```

**What it does:**
- Stages files for git
- Shows what will be committed
- Nix needs all files to be tracked

### A Node Tool Fails With `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`

This means a Node binary is resolving TLS roots through an empty trust store. It happens with
Homebrew-built Node, which looks in `/opt/homebrew/etc/openssl@3` rather than at the system
bundle.

Check which Node you are actually running:

```bash
which node
node -p "process.config.variables.node_shared_openssl"
```

If `which node` is `/opt/homebrew/bin/node`, a leftover Homebrew Node is shadowing the Nix one.
Remove it, or check that `~/.npm-global/bin` is ahead of `/opt/homebrew/bin` on your `PATH`.

`home.nix` sets `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` for exactly this case,
so confirm it is exported in your shell:

```bash
echo $NODE_EXTRA_CA_CERTS
```

**Expected output:** `/etc/ssl/certs/ca-certificates.crt`. If it's empty, run `exec zsh` to pick
up the current session variables.

### `git status` Shows Changes You Never Made

`home.nix` links `~/.config/herdr` as a whole directory and, under `~/.claude`, exactly two
files: `settings.json` and `CLAUDE.md` (which points at `home/AGENTS.md`). Everything else in
`~/.claude` - `hooks/`, `projects/`, `history.jsonl` - is ordinary local state that never reaches
this repo. The herdr directory's runtime noise is gitignored, but the linked files are tracked,
so a tool editing one of them shows up as a change you never made.

The one you are most likely to hit: when herdr installs or updates its Claude integration it adds
a `SessionStart` hook to `home/.claude/settings.json` with your home directory spelled out in
full. That hook is correct on your machine and wrong everywhere else, so it is never committed.
Restore the file and carry on:

```bash
git checkout -- home/.claude/settings.json
```

Leave the integration installed - it is what tells herdr whether a Claude pane is working or
idle. `./tests/run.sh` fails with this same instruction if the file still carries an absolute
`/Users/` path, and CI runs the same suite on every pull request.

Claude itself writes to the same file once on a 1M-context account, rewriting `"model": "opus"`
to `"opus[1m]"`. Different diff, same remedy, and no absolute path for the check to catch - see
the AGENTS.md note on the `model` key.

### Homebrew Packages Were Deleted

The config has `cleanup = "zap"` enabled, which removes packages not in the list. If packages disappeared:

1. Check what's in `configuration-darwin.nix`:
```bash
grep -A 10 "brews = \[" ~/.dotfiles/configuration-darwin.nix
```

2. Add them back:
```bash
nano ~/.dotfiles/configuration-darwin.nix
```

3. Rebuild:
```bash
./rebuild.sh
```

---

## Summary

**First time setup:**
```bash
git clone https://github.com/modzs/dotfiles.git
cd dotfiles
./bootstrap.sh
```

**After making changes:**
```bash
cd ~/.dotfiles
./rebuild.sh
```

**To pull changes from the repo:**
```bash
cd ~/.dotfiles
git pull
./rebuild.sh
```

**Key commands:**
- `./rebuild.sh` - Apply configuration changes
- `nano ~/.dotfiles/home.nix` - Edit home-manager config
- `nano ~/.dotfiles/configuration-darwin.nix` - Edit macOS system settings and Homebrew packages
- `nix search nixpkgs package-name` - Find a package to install
- `npm view <cli> versions --json` - Check versions before bumping a pin in `npmGlobals`
- `exec zsh` - Reload shell after changes

---

## Quick Reference: What's Where

| File | Purpose |
|------|---------|
| `flake.nix` | Nix configuration entry point (the `mac` output) |
| `home.nix` | User packages, shell, editor config |
| `configuration-darwin.nix` | macOS system settings, Homebrew |
| `bootstrap.sh` | First-time setup script |
| `rebuild.sh` | Apply configuration changes |
| `home/` | Actual config files (symlinked) |

---

Need help? Check the main README.md for more detailed information about architecture and how symlinks work.
