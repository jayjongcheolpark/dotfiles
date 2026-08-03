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

    # Shared Homebrew for every admin (nina + jaypark). Both are already in
    # the admin group. nix-homebrew / brew bundle run as primaryUser and can
    # leave owner-only modes; reassert group write after each switch.
    # - g+rwX: existing files/dirs writable by admin
    # - setgid on dirs: new entries inherit group admin
    # - directory ACLs with file_inherit: new files stay admin-writable
    #   even under umask 022 (without walking every file in Cellar)
    # - exception: share/zsh must NOT be group-writable — zsh compinit treats
    #   group-writable fpath dirs as insecure and prompts every shell start
    if [ -d /opt/homebrew ]; then
      echo "sharing /opt/homebrew with admin group..." >&2
      /usr/bin/chgrp -R admin /opt/homebrew
      /bin/chmod -R g+rwX /opt/homebrew
      /usr/bin/find /opt/homebrew -type d -exec /bin/chmod g+s {} +
      /usr/bin/find /opt/homebrew -type d -exec /bin/chmod -N {} + 2>/dev/null || true
      /usr/bin/find /opt/homebrew -type d -exec /bin/chmod +a "group:admin allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" {} + 2>/dev/null || true
      if [ -d /opt/homebrew/share/zsh ]; then
        /bin/chmod -R g-w /opt/homebrew/share/zsh
        /usr/bin/find /opt/homebrew/share/zsh -type d -exec /bin/chmod g-s {} +
        /usr/bin/find /opt/homebrew/share/zsh -type d -exec /bin/chmod -N {} + 2>/dev/null || true
        /bin/chmod -R g+rX /opt/homebrew/share/zsh
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
    ];
    casks = [
      "ghostty"
      "tailscale-app"  # Homebrew renamed the Tailscale cask from "tailscale"
      "claude-code"
      "1password"
      # Secrets manager for agent/CLI hardening.
      # Upstream cask is arm64-only (depends_on arch: :arm64); Intel Macs cannot install it.
      "automic-vault/isotopes/automic-vault"
    ];
  };
}
