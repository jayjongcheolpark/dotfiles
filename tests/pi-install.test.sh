#!/usr/bin/env bash
# Pi CLI install + Kun's published agent config stay wired in Home Manager.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

home_nix=$(cat "$ROOT/home.nix")
assert_contains "$home_nix" "https://pi.dev/install.sh" \
  "home.nix ensurePi must prefer the official curl installer"
assert_contains "$home_nix" "npm install -g --ignore-scripts @earendil-works/pi-coding-agent" \
  "home.nix ensurePi must fall back to npm when curl is missing"

curl_line=$(awk '/https:\/\/pi.dev\/install.sh/{print NR; exit}' "$ROOT/home.nix")
npm_line=$(awk '/npm install -g --ignore-scripts @earendil-works\/pi-coding-agent/{print NR; exit}' "$ROOT/home.nix")
[ -n "$curl_line" ] && [ -n "$npm_line" ] && [ "$curl_line" -lt "$npm_line" ] \
  || fail "home.nix must try the curl installer before npm"

settings=$(cat "$ROOT/home/.pi/agent/settings.json")
assert_contains "$settings" "npm:pi-web-access@0.14.0" \
  "settings.json must pin pi-web-access"
assert_contains "$settings" "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6" \
  "settings.json must pin pi-extension-codex-fast-mode"
assert_contains "$settings" "git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055" \
  "settings.json must pin pi-openai-server-compaction"
assert_contains "$settings" "npm:pi-multi-account" \
  "settings.json must declare pi-multi-account"
assert_contains "$settings" '"theme": "rose-pine-moon"' \
  "settings.json must use rose-pine-moon"
assert_contains "$settings" '"defaultModel": "claude-opus-4-8"' \
  "settings.json must keep the current default model"

models=$(cat "$ROOT/home/.pi/agent/models.json")
assert_contains "$models" "gpt-5.6-luna" \
  "models.json must override openai-codex context windows"
assert_contains "$models" "kimi-coding-account-2" \
  "models.json must keep the Kimi coding provider"
assert_not_contains "$models" "127.0.0.1" \
  "models.json must not pin Cursor's ephemeral localhost proxy"

[ -f "$ROOT/home/.pi/agent/provider-failover.json" ] \
  || fail "provider-failover.json is missing"

[ -f "$ROOT/home/.pi/agent/themes/rose-pine-moon.json" ] \
  || fail "rose-pine-moon theme is missing"
[ -f "$ROOT/home/.pi/agent/extensions/terminal-status-title.js" ] \
  || fail "terminal-status-title extension is missing"
[ -f "$ROOT/home/.pi/agent/extensions/calm/index.ts" ] \
  || fail "Calm extension is missing"

pass "Pi install and Kun agent config are declared"
