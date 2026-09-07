#!/usr/bin/env bash
# Native herdr install: no Homebrew formula, official installer on activation.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

brews=$(sed -n '/brews = \[/,/\];/p' "$ROOT/configuration.nix")
assert_not_contains "$brews" "herdr" \
  "configuration.nix homebrew.brews must not list herdr"

home_nix=$(cat "$ROOT/home.nix")
assert_contains "$home_nix" "https://herdr.dev/install.sh" \
  "home.nix ensureHerdr must use the native installer URL"
assert_not_contains "$home_nix" "brew install herdr" \
  "home.nix must not install herdr via Homebrew"

readme=$(cat "$ROOT/README.md")
assert_contains "$readme" "herdr.dev/install.sh" \
  "README must document the native installer"

pass "herdr is installed natively, not via Homebrew"
