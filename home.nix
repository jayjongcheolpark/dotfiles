{ config, pkgs, lib, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # herdr plugins to ensure on every home-manager activation.
  # Plugin *packages* are installed under ~/.config/herdr/plugins/github/ (gitignored).
  # Authored plugin config lives under home/.config/herdr/plugins/config/<id>/.
  herdrPlugins = [
    "cloudmanic/herdr-plus"
  ];
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    # fzf via programs.fzf (installs binary + zsh keybindings)
    jq        # json on the command line
    lazygit
    gh        # GitHub CLI
    neovim
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    # asdf 0.16+ (Homebrew formula) stores plugins/installs here. Keep it
    # out of zshrc-only so non-interactive zsh (and hm-session-vars) see it.
    ASDF_DATA_DIR = "${config.home.homeDirectory}/.asdf";
  };

  # Grok CLI (installer used to drop this into a hand-written ~/.zshrc).
  # ~/.local/bin: Anthropic native Claude Code (`claude`) and other installers.
  # ~/.asdf/shims: asdf 0.16+ - shim → `asdf exec`; brew puts `asdf` on PATH.
  home.sessionPath = [
    "${config.home.homeDirectory}/.asdf/shims"
    "${config.home.homeDirectory}/.grok/bin"
    "${config.home.homeDirectory}/.local/bin"
  ];

  # Fuzzy finder + zsh widgets (jaypark had oh-my-zsh plugin "fzf"):
  #   Ctrl-R  → shell history
  #   Ctrl-T  → files under cwd
  #   Alt-C   → cd into directory
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
  };

  # Smart cd (old hand-written zshrc: `eval "$(zoxide init zsh)"`):
  #   z foo   → jump to frecent directory matching foo
  #   zi foo  → interactive picker (needs fzf)
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;           # tab completion (compinit)
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    # Login shells (.zprofile). Replaces the old hand-written zprofile that
    # still pointed at nvm / asdf-x86 after the Intel → Apple Silicon move.
    profileExtra = ''
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      # Native CLIs (claude) ahead of Homebrew so a leftover cask cannot shadow.
      export PATH="$HOME/.local/bin:$PATH"
      # asdf 0.16+: no need to source asdf.sh - shims + brew `asdf` are enough.
      export ASDF_DATA_DIR="''${ASDF_DATA_DIR:-$HOME/.asdf}"
      case ":$PATH:" in
        *":$ASDF_DATA_DIR/shims:"*) ;;
        *) export PATH="$ASDF_DATA_DIR/shims:$PATH" ;;
      esac
    '';
    initContent = ''
      bindkey '^f' autosuggest-accept
      # History substring search on arrows (old zshrc)
      bindkey '^[[A' history-search-backward
      bindkey '^[[B' history-search-forward
      # Grok CLI zsh completions (if present). Prepend fpath before any
      # late re-compinit callers; home-manager already ran compinit above.
      if [ -d "$HOME/.grok/completions/zsh" ]; then
        fpath=("$HOME/.grok/completions/zsh" $fpath)
      fi
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
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
      name = "Jay Park";
      email = "jay.jongcheol.park@gmail.com";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/ghostty";
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
  home.file.".pi/agent/provider-failover.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/provider-failover.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Install herdr plugins that are declared above but not yet registered.
  # herdr itself is a Homebrew brew (see configuration.nix); brew may not be
  # on activation PATH, so pin the common prefixes.
  # Idempotent: skips when the plugin_id is already enabled.
  home.activation.installHerdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    if ! command -v herdr >/dev/null 2>&1; then
      echo "herdr not on PATH; skip herdr plugin install" >&2
    else
      plugin_list_json="$(herdr plugin list --json 2>/dev/null || true)"
      ${lib.concatMapStringsSep "\n" (spec: ''
        plugin_spec=${lib.escapeShellArg spec}
        # cloudmanic/herdr-plus -> cloudmanic.herdr-plus
        plugin_id="$(printf '%s' "$plugin_spec" | tr '/' '.')"
        if printf '%s' "$plugin_list_json" | ${pkgs.jq}/bin/jq -e \
          --arg id "$plugin_id" \
          'any(.result.plugins[]?; .plugin_id == $id and .enabled == true)' \
          >/dev/null 2>&1; then
          echo "herdr plugin already installed: $plugin_id" >&2
        else
          echo "installing herdr plugin: $plugin_spec" >&2
          $DRY_RUN_CMD herdr plugin install "$plugin_spec" --yes
        fi
      '') herdrPlugins}
    fi
  '';

  # Native Claude Code CLI (`~/.local/bin/claude`). Homebrew's cask lags
  # Anthropic releases, so do not put `claude-code` back in homebrew.casks.
  # Re-running the installer is idempotent and pulls the latest stable.
  home.activation.ensureClaudeCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${config.home.homeDirectory}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
    echo "installing/updating Claude Code via native installer..." >&2
    $DRY_RUN_CMD bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
      || echo "warning: native Claude Code installer failed" >&2
  '';

  # Official Pi CLI (`pi`). Prefer the curl installer, then npm. Skip Homebrew
  # so updates are not stuck on the core formula.
  home.activation.ensurePi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${config.home.homeDirectory}/.asdf/shims:${config.home.homeDirectory}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
    if command -v pi >/dev/null 2>&1; then
      echo "pi already available: $(command -v pi)" >&2
    elif command -v curl >/dev/null 2>&1; then
      echo "installing Pi via native installer..." >&2
      $DRY_RUN_CMD bash -c 'curl -fsSL https://pi.dev/install.sh | sh' \
        || echo "warning: native Pi installer failed" >&2
      if command -v asdf >/dev/null 2>&1; then
        $DRY_RUN_CMD asdf reshim nodejs || true
      fi
    elif command -v npm >/dev/null 2>&1; then
      echo "installing Pi via npm..." >&2
      $DRY_RUN_CMD npm install -g --ignore-scripts @earendil-works/pi-coding-agent \
        || echo "warning: Pi npm install failed" >&2
      if command -v asdf >/dev/null 2>&1; then
        $DRY_RUN_CMD asdf reshim nodejs || true
      fi
    else
      echo "curl and npm not on PATH; cannot install Pi" >&2
    fi
  '';
}
