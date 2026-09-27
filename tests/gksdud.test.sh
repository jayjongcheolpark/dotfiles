#!/usr/bin/env bash
# gksdud: Homebrew cask plus the user choices from the live defaults domain.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

config=$(cat "$ROOT/configuration.nix")

taps=$(sed -n '/taps = \[/,/];/p' "$ROOT/configuration.nix")
assert_contains "$taps" 'name = "codingnoye/tap"' \
  "configuration.nix homebrew.taps must include codingnoye/tap"
assert_contains "$taps" "trusted = true" \
  "third-party taps must be trusted so activation can install their casks"

casks=$(sed -n '/casks = \[/,/];/p' "$ROOT/configuration.nix")
assert_contains "$casks" '"codingnoye/tap/gksdud"' \
  "configuration.nix homebrew.casks must list codingnoye/tap/gksdud"

prefs=$(sed -n '/"io.gksdud.inputswitch" = {/,/};/p' "$ROOT/configuration.nix")
assert_contains "$prefs" "active = true" \
  "gksdud active must be the live boolean"
assert_contains "$prefs" "iconStyle = 2" \
  "gksdud iconStyle must be 2"
assert_contains "$prefs" 'source = "30064771129"' \
  "gksdud source must be the Caps Lock usage string"
assert_contains "$prefs" 'target = "F19"' \
  "gksdud target must be F19"
assert_not_contains "$prefs" "records" \
  "gksdud prefs must not persist records"
assert_not_contains "$prefs" "knownKeyboards" \
  "gksdud prefs must not persist knownKeyboards"
assert_not_contains "$prefs" "keyboardRecordsBoot" \
  "gksdud prefs must not persist keyboardRecordsBoot"
assert_not_contains "$prefs" "managedShortcutKeyCode" \
  "gksdud prefs must not persist managedShortcutKeyCode"
assert_not_contains "$prefs" "BackedUp" \
  "gksdud prefs must not persist backup flags"
assert_not_contains "$prefs" "updates." \
  "gksdud prefs must not persist updates.*"

assert_contains "$config" "TISRomanSwitchState = 0" \
  "Caps Lock ABC switch must stay off"

assert_contains "$config" 'extraFlags = [ "--force" ]' \
  "homebrew onActivation must keep --force"
assert_not_contains "$config" "no_quarantine" \
  "configuration must not disable quarantine for every cask"
assert_contains "$config" 'if [ -e /Applications/gksdud.app ]; then' \
  "a missing gksdud app must not fail activation"
assert_contains "$config" 'sudo -u ${user} /usr/bin/xattr -dr com.apple.quarantine /Applications/gksdud.app' \
  "activation must clear quarantine on /Applications/gksdud.app as the Homebrew user"

# Comments may name F19. The Python writer must not hardcode that remap,
# and it must not turn the stock previous-input-source chord back on.
hotkey=$(sed -n "/<<'PY'/,/^PY$/p" "$ROOT/configuration.nix")
assert_contains "$hotkey" 'entry["enabled"] = False' \
  "activation must turn off hotkey 60 while it is still the stock chord"
assert_contains "$hotkey" 'stock = [32, 49, 262144]' \
  "activation must recognize the stock previous-input-source chord"
assert_not_contains "$hotkey" '["enabled"] = True' \
  "activation must not enable symbolic hotkeys 60 or 61"
assert_not_contains "$hotkey" "65535" \
  "activation must not hardcode the F19 symbolic-hotkey parameters"
assert_not_contains "$config" '("60", "61")' \
  "activation must not force symbolic hotkeys 60 and 61 on"

readme=$(cat "$ROOT/README.md")
assert_contains "$readme" "Accessibility" \
  "README must document the manual Accessibility grant"
assert_contains "$readme" "once per machine" \
  "README must say Accessibility permission is still once per machine"
assert_contains "$readme" "not notarized" \
  "README must say gksdud is self-signed and not notarized"
assert_contains "$readme" "no longer needed after a rebuild" \
  "README must say Gatekeeper approval is no longer needed after a rebuild"
assert_not_contains "$config" "Ctrl+Space" \
  "configuration.nix must describe gksdud Caps Lock to F19, not Ctrl+Space"
assert_not_contains "$readme" "Ctrl+Space" \
  "README must describe gksdud Caps Lock to F19, not Ctrl+Space"

pass "gksdud cask, preferences, and manual steps are declared"
