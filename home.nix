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
  # ~/.local/bin: Anthropic's native `claude` installer (fallback if not using the brew cask).
  # ~/.asdf/shims: asdf 0.16+ — shim → `asdf exec`; brew puts `asdf` on PATH.
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

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    # Login shells (.zprofile). Replaces the old hand-written zprofile that
    # still pointed at nvm / asdf-x86 after the Intel → Apple Silicon move.
    profileExtra = ''
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      # asdf 0.16+: no need to source asdf.sh — shims + brew `asdf` are enough.
      export ASDF_DATA_DIR="''${ASDF_DATA_DIR:-$HOME/.asdf}"
      case ":$PATH:" in
        *":$ASDF_DATA_DIR/shims:"*) ;;
        *) export PATH="$ASDF_DATA_DIR/shims:$PATH" ;;
      esac
    '';
    initContent = ''
      bindkey '^f' autosuggest-accept
      # Grok CLI zsh completions (if present)
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

  # Ensure Claude Code CLI is present and executable.
  # Primary install is the Homebrew cask `claude-code` (configuration.nix).
  # This activation covers fresh machines / zap recovery / the 644-bit cask bug.
  home.activation.ensureClaudeCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    ensure_claude_x() {
      local link target
      link="$(command -v claude 2>/dev/null || true)"
      if [ -z "$link" ]; then
        return 1
      fi
      if [ -L "$link" ]; then
        target="$(/usr/bin/readlink "$link")"
        case "$target" in
          /*) ;;
          *) target="$(/usr/bin/dirname "$link")/$target" ;;
        esac
      else
        target="$link"
      fi
      if [ -f "$target" ] && [ ! -x "$target" ]; then
        echo "restoring execute bit on claude ($target)..." >&2
        $DRY_RUN_CMD /bin/chmod a+x "$target"
      fi
      # Re-check: command -v ignores non-executable files.
      command -v claude >/dev/null 2>&1
    }

    if ensure_claude_x; then
      echo "claude already available: $(command -v claude)" >&2
    elif command -v brew >/dev/null 2>&1; then
      echo "installing Claude Code via Homebrew cask..." >&2
      $DRY_RUN_CMD brew install --cask claude-code
      ensure_claude_x || echo "warning: claude still not executable after brew install" >&2
    else
      echo "brew not on PATH; cannot install claude-code cask" >&2
    fi
  '';
}
