# How to Use These Dotfiles

This guide walks you through setting up your development environment using this dotfiles repo on macOS. This repo is macOS-only.

## Table of Contents

1. [macOS Setup](#macos-setup)
2. [Daily Workflow](#daily-workflow)
3. [Customizing Your Setup](#customizing-your-setup)

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

5. **Runs the first build**
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

### Step 5: Fix the Git Identity

`home.nix` ships with a concrete git name and email already filled in - the repo owner's, not yours. Until you change it, every commit you make on this machine is attributed to the wrong person.

Check what you actually have after the switch:

```bash
git config --get user.name
git config --get user.email
```

**Expected output:** your own name and email. If you see anything else, edit the `programs.git.settings.user` attribute in `home.nix`, then run `./rebuild.sh`. See [Setting Git Identity Declaratively](#setting-git-identity-declaratively) below for the exact block.

---

## Daily Workflow

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

### Setting Git Identity Declaratively

Edit `home.nix`:

```bash
nano ~/.dotfiles/home.nix
```

Find the `programs.git` attribute and update:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Your Name";
    email = "your@email.com";
  };
};
```

Then apply:

```bash
./rebuild.sh
```

**What it does:**
- Sets your git name and email configuration
- Applied every time you rebuild
- No need to manually `git config` again

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

### Adding Work-Specific Configuration (Employer Machine)

If you're on a work machine and need separate config:

Create a `.gitconfig.local` file in your home directory:

```bash
cat > ~/.gitconfig.local <<'EOF'
[user]
    name = Work Name
    email = work@company.com
EOF
```

**What it does:**
- Creates a local git config file for work identity
- `programs.git.includes` in `home.nix` pulls it in after the identity set there, so it overrides your name and email
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

No further wiring is needed: `home.nix` already sources `~/.zshrc.local` from `programs.zsh.initContent` and pulls in `~/.gitconfig.local` through `programs.git.includes`. Home Manager writes that include after the identity set in `home.nix`, so `~/.gitconfig.local` overrides your name and email on a work machine, and is simply ignored when it isn't there.

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

**Key commands:**
- `./rebuild.sh` - Apply configuration changes
- `nano ~/.dotfiles/home.nix` - Edit home-manager config
- `nano ~/.dotfiles/configuration-darwin.nix` - Edit macOS system settings and Homebrew packages
- `nix search nixpkgs package-name` - Find a package to install
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
