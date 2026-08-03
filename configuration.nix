{ user, ... }:

{
  # Official Nix on Intel: let nix-darwin manage the daemon and nix.conf.
  # On Apple Silicon with Determinate Nix, set this to false instead
  # (Determinate already manages the daemon).
  nix.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "x86_64-darwin"; # use aarch64-darwin for Apple Silicon

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;

      # Keyboard settings panel (spelling / substitutions) — all off.
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
    };
    dock.autohide = true;
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
  '';
  nix-homebrew = {
    enable = true;
    inherit user;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    brews = [
      "herdr"
    ];
    casks = [
      "ghostty"
      "tailscale-app"  # Homebrew renamed the Tailscale cask from "tailscale"
      "claude-code"
    ];
  };
}
