{ config, lib, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # npm's global prefix. The Nix node's own prefix is a read-only store path, so
  # `npm install -g` needs somewhere writable. Putting it here - and NOT in
  # /opt/homebrew, which is where a Homebrew node would put it - is what keeps
  # these CLIs out of reach of `homebrew.onActivation.cleanup = "zap"`.
  npmPrefix = "${config.home.homeDirectory}/.npm-global";

  # Agent CLIs published on npm but absent from nixpkgs. Pinned on purpose:
  # unpinned, a routine `./rebuild.sh` could silently change tool versions.
  # Bump a version here, then run ./rebuild.sh.
  npmGlobals = {
    "gh-axi" = "0.1.35";
    "chrome-devtools-axi" = "0.1.34";
    "lavish-axi" = "0.1.67";
    "tasks-axi" = "0.2.5";
    "quota-axi" = "0.1.40";
  };
  npmSpecs = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: version: "${name}@${version}") npmGlobals
  );
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    # Node itself, so it is declared and pinned by flake.lock rather than left
    # to Homebrew, where `cleanup = "zap"` would delete it on the next switch.
    nodejs_26
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  # Node resolves TLS roots through OpenSSL's default store. The Nix node finds
  # /etc/ssl/certs/ca-certificates.crt on its own, but a Homebrew-linked node
  # looks in /opt/homebrew/etc/openssl@3, which is empty on this machine - so
  # every HTTPS request from such a node dies with UNABLE_TO_GET_ISSUER_CERT_LOCALLY,
  # npm installs included. Pointing every Node at the bundle nix-darwin already
  # manages (security.pki.installCACerts) removes that whole failure mode.
  home.sessionVariables.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";

  home.sessionVariables.NPM_CONFIG_PREFIX = npmPrefix;
  home.sessionPath = [
    "${npmPrefix}/bin"
    # `no-mistakes` ships its own binary here; see README for the one-time install.
    "${config.home.homeDirectory}/.no-mistakes/bin"
  ];

  # The npm CLIs above are not in nixpkgs, so Home Manager installs them into the
  # writable prefix instead. The logic lives in lib/npm-globals.sh - a real script,
  # so tests/npm-globals.test.sh can execute it - and the pinned versions are passed
  # in, so npmGlobals above stays the single source of truth. Version-guarded, so a
  # rebuild with nothing to change touches the network zero times, and a failed
  # install warns instead of aborting the switch.
  home.activation.agentNpmCLIs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # DRY_RUN reaches activation from the caller's environment, already exported,
    # so this is a no-op today. It is here so that a Home Manager which set it as
    # a plain shell variable could not silently turn a dry run into real installs
    # in the child. Exporting only when it is set keeps the script's
    # `set, even if empty` test meaning exactly what it did inline.
    if [ -n "''${DRY_RUN+x}" ]; then export DRY_RUN; fi

    ${pkgs.bash}/bin/bash ${./lib/npm-globals.sh} \
      "${pkgs.nodejs_26}/bin" "${npmPrefix}" ${npmSpecs}
  '';

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
      # Machine-specific overrides (work laptops); untracked, absent is fine.
      [[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
    '';
    shellAliases = {
      ".." = "cd ..";
      "add" = "git add .";
      "push" = "git push";
      "pull" = "git pull";
      "m" = "git switch main";
      "cc" = "claude --dangerously-skip-permissions";
      "co" = "codex --full-auto";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };
  
  programs.git = {
    enable = true;
    settings.user = {
      name = "modzs";
      email = "windom.jh@gmail.com";
    };
    # Home Manager appends this include after the settings above, so a
    # work machine's untracked ~/.gitconfig.local overrides the identity.
    includes = [ { path = "~/.gitconfig.local"; } ];
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
