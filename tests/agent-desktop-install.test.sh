#!/usr/bin/env bash
# agent-desktop CLI install + its agent skills stay wired in Home Manager.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

home_nix=$(cat "$ROOT/home.nix")
assert_contains "$home_nix" "home.activation.ensureAgentDesktop" \
  "home.nix must declare the ensureAgentDesktop activation step"
assert_contains "$home_nix" "npm install -g --ignore-scripts agent-desktop" \
  "home.nix ensureAgentDesktop must install the CLI via npm"
assert_contains "$home_nix" "npx -y skills@1.7.4 add https://github.com/vercel-labs/agent-desktop" \
  "home.nix ensureAgentDesktop must install the agent-desktop skills"
assert_contains "$home_nix" "-g -a claude-code -y" \
  "agent-desktop skills must install globally for Claude Code"

readme=$(cat "$ROOT/README.md")
assert_contains "$readme" "Accessibility permission" \
  "README must tell the user to grant Accessibility permission by hand"

pass "agent-desktop install and skills are declared"
