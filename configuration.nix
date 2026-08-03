{ user, ... }:

{
  # Determinate Nix (Apple Silicon default) manages its own daemon — do not
  # let nix-darwin take over. On Intel with official Nix, set this to true
  # so nix-darwin manages the daemon and nix.conf.
  nix.enable = false;
  # With nix.enable = false these settings are not applied by nix-darwin;
  # bootstrap.sh and Determinate already enable flakes. Kept for the Intel
  # path when nix.enable is flipped back to true.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel

  # Touch ID / Apple Watch for sudo (replaces a typical /etc/pam.d/sudo_local).
  # Mac Studio has no Touch ID sensor; Apple Watch still uses pam_tid.so.
  security.pam.services.sudo_local.touchIdAuth = true;

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };

  # asdf shims for every process that uses path_helper (login shells, many GUI
  # apps, Claude Code SessionStart hooks). Homebrew is already in
  # /etc/paths.d/homebrew → /opt/homebrew/bin (asdf binary). Without this,
  # shims never appear on PATH outside interactive zsh, so `node` fails even
  # though ~/.asdf/installs/* is populated.
  environment.etc."paths.d/40-asdf-shims".text = "/Users/${user}/.asdf/shims\n";

  # macOS Remote Login (sshd on port 22). Needed for herdr --remote / SSH
  # over Tailscale. nix-darwin enables com.openssh.sshd via launchctl.
  services.openssh.enable = true;
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = false;  # keep the menu bar always visible
      AppleShowAllExtensions = true;

      # Keyboard settings panel (spelling / substitutions) — all off.
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
    };
    dock.autohide = false;  # keep the Dock always visible
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click

    # Language / region / input sources (not all first-class options).
    # Preferred languages: English UI first, Korean available.
    # Input sources: Canadian + 2-Set Hangul (두벌식), matching the
    # System Settings → Keyboard → Input Sources layout.
    # HIToolbox writes alone often don't refresh the Settings list until
    # TextInput agents restart (handled in activationScripts below) or a logout.
    CustomUserPreferences = {
      NSGlobalDomain = {
        AppleLanguages = [ "en-CA" "ko" ];
        AppleLocale = "en_CA";
      };
      "com.apple.TextInputMenu" = {
        visible = 1;  # Show Input menu in menu bar
      };
      "com.apple.HIToolbox" = {
        AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.Canadian";
        AppleEnabledInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 29;
            "KeyboardLayout Name" = "Canadian";
          }
          {
            "Bundle ID" = "com.apple.inputmethod.Korean";
            InputSourceKind = "Keyboard Input Method";
          }
          {
            "Bundle ID" = "com.apple.inputmethod.Korean";
            "Input Mode" = "com.apple.inputmethod.Korean.2SetKorean";
            InputSourceKind = "Input Mode";
          }
          {
            "Bundle ID" = "com.apple.CharacterPaletteIM";
            InputSourceKind = "Non Keyboard Input Method";
          }
          {
            "Bundle ID" = "com.apple.inputmethod.EmojiFunctionRowItem";
            InputSourceKind = "Non Keyboard Input Method";
          }
        ];
        AppleSelectedInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 29;
            "KeyboardLayout Name" = "Canadian";
          }
        ];
      };
    };
  };

  # HIToolbox defaults alone do not fully register Input Methods for the
  # menu bar / switcher on modern macOS. After defaults are written:
  #  1) enable Canadian + 2-Set Hangul via Carbon TIS APIs
  #  2) turn on Ctrl+Space input-source hotkeys (off by default)
  #  3) bounce text-input agents
  # System Settings → Input Sources often still only lists keyboard *layouts*
  # (Canadian) and omits *input methods* (Korean) — use the menu bar or
  # Ctrl+Space instead; `scripts/enable-korean-input.swift` is authoritative.
  system.activationScripts.postActivation.text = ''
    echo "enabling Korean 2-Set Hangul + Canadian input sources..." >&2
    # Activation runs as root; TIS and user prefs must run as the desktop user.
    sudo -u ${user} /usr/bin/swift /Users/${user}/.dotfiles/scripts/enable-korean-input.swift 2>&1 || true

    echo "enabling Ctrl+Space input source hotkeys..." >&2
    # 60 = previous source (Ctrl+Space), 61 = next (Ctrl+Opt+Space).
    # PlistBuddy is unreliable with int-keyed dicts; use defaults export/import.
    sudo -u ${user} /usr/bin/python3 - <<'PY' || true
import plistlib, subprocess, tempfile, os
raw = subprocess.check_output(["defaults", "export", "com.apple.symbolichotkeys", "-"])
pl = plistlib.loads(raw)
keys = pl.setdefault("AppleSymbolicHotKeys", {})
for k in list(keys.keys()):
    if str(k) in ("60", "61"):
        keys[k]["enabled"] = True
with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as f:
    plistlib.dump(pl, f)
    tmp = f.name
subprocess.check_call(["defaults", "import", "com.apple.symbolichotkeys", tmp])
os.unlink(tmp)
PY
    sudo -u ${user} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

    killall TextInputMenuAgent 2>/dev/null || true
    killall TextInputSwitcher 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true

    # Single-user Homebrew for ${user}. Ownership must match primaryUser so
    # brew / nix-homebrew can write without sudo, and so zsh compinit does
    # not treat group-writable fpath dirs as insecure every shell start.
    # Strips any leftover multi-admin setgid / ACLs / group-write from older
    # nina+jaypark sharing.
    if [ -d /opt/homebrew ]; then
      echo "owning /opt/homebrew as ${user}..." >&2
      /usr/sbin/chown -R ${user}:admin /opt/homebrew
      /usr/bin/find /opt/homebrew -type d -exec /bin/chmod g-s {} + 2>/dev/null || true
      /usr/bin/find /opt/homebrew -exec /bin/chmod -N {} + 2>/dev/null || true
      /bin/chmod -R go-w /opt/homebrew

      # Some casks (e.g. claude-code) have landed in Caskroom as 644, so
      # /opt/homebrew/bin/<name> resolves but shells report "permission denied".
      # Restore +x on any Caskroom target linked from bin/.
      for link in /opt/homebrew/bin/*; do
        [ -L "$link" ] || continue
        target=$(/usr/bin/readlink "$link")
        case "$target" in
          /*) ;;
          *) target="$(/usr/bin/dirname "$link")/$target" ;;
        esac
        case "$target" in
          /opt/homebrew/Caskroom/*) ;;
          *) continue ;;
        esac
        if [ -f "$target" ] && [ ! -x "$target" ]; then
          echo "restoring execute bit on $(basename "$link") ($target)..." >&2
          /bin/chmod a+x "$target" || true
        fi
      done

      # Casks (e.g. Ghostty) symlink zsh completions into site-functions from
      # /Applications/*.app. If that app was installed by another macOS user,
      # compaudit rejects the file (owner must be root or $EUID). SIP often
      # blocks chown on app bundles, so materialize those links as real files
      # owned by ${user}.
      sitefn=/opt/homebrew/share/zsh/site-functions
      if [ -d "$sitefn" ]; then
        for f in "$sitefn"/_*; do
          [ -L "$f" ] || continue
          target=$(/usr/bin/readlink "$f")
          case "$target" in
            /*) ;;
            *) target="$(/usr/bin/dirname "$f")/$target" ;;
          esac
          [ -e "$target" ] || continue
          owner=$(/usr/bin/stat -f %Su "$target")
          if [ "$owner" != "${user}" ] && [ "$owner" != "root" ]; then
            echo "materializing zsh completion $(basename "$f") (target owned by $owner)..." >&2
            tmp=$(/usr/bin/mktemp)
            /bin/cp "$target" "$tmp"
            /bin/rm -f "$f"
            /bin/mv "$tmp" "$f"
            /usr/sbin/chown ${user}:admin "$f"
            /bin/chmod 644 "$f"
          fi
        done
      fi
    fi
  '';
  nix-homebrew = {
    enable = true;
    inherit user;
    # Adopt an existing /opt/homebrew (or /usr/local) install instead of
    # aborting. Keeps already-installed packages; onActivation.cleanup = "zap"
    # still removes anything not listed in homebrew.brews/casks below.
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    # Third-party tap for Automic Vault (not in homebrew-cask core).
    # trusted = true is required under Homebrew's tap-trust rules during activation.
    taps = [
      {
        name = "automic-vault/isotopes";
        trusted = true;
      }
    ];
    brews = [
      "herdr"
      "bun"  # JS runtime / package manager (e.g. constructease/app)
      # Version manager for constructease (.tool-versions: nodejs, bun, …).
      # Data/plugins stay in ~/.asdf; without this entry, onActivation.cleanup
      # = "zap" removes asdf on every switch.
      "asdf"
    ];
    casks = [
      "ghostty"
      "tailscale-app"  # Homebrew renamed the Tailscale cask from "tailscale"
      # Claude Code CLI (`claude` on PATH via /opt/homebrew/bin/claude).
      # home.activation.ensureClaudeCode also reinstalls/fixes +x if missing.
      "claude-code"
      "1password"
      # Secrets manager for agent/CLI hardening.
      # Upstream cask is arm64-only (depends_on arch: :arm64); Intel Macs cannot install it.
      "automic-vault/isotopes/automic-vault"
    ];
  };
}
