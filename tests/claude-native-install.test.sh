#!/usr/bin/env bash
# Native Claude Code install: no Homebrew cask, official installer on activation.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

casks=$(sed -n '/casks = \[/,/\];/p' "$ROOT/configuration.nix")
assert_not_contains "$casks" "claude-code" \
  "configuration.nix homebrew.casks must not list claude-code"

home_nix=$(cat "$ROOT/home.nix")
assert_contains "$home_nix" "https://claude.ai/install.sh" \
  "home.nix ensureClaudeCode must use the native installer URL"
assert_not_contains "$home_nix" "brew install --cask claude-code" \
  "home.nix must not install Claude Code via Homebrew"
assert_contains "$home_nix" 'CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"' \
  "home.nix must pin CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING as a session variable"
assert_contains "$home_nix" 'CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1"' \
  "home.nix must pin CLAUDE_CODE_DISABLE_AUTO_MEMORY as a session variable"
assert_contains "$home_nix" 'CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1"' \
  "home.nix must pin CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY as a session variable"
assert_contains "$home_nix" 'CLAUDE_CODE_AUTO_COMPACT_WINDOW = "500000"' \
  "home.nix must pin CLAUDE_CODE_AUTO_COMPACT_WINDOW as a session variable"

readme=$(cat "$ROOT/README.md")
assert_contains "$readme" "claude.ai/install.sh" \
  "README must document the native installer"

pass "Claude Code is installed natively, not via Homebrew cask"
