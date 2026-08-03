#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles

# sudo uses a secure PATH that does not include /run/current-system/sw/bin,
# so a bare `darwin-rebuild` fails even after a successful first switch.
find_darwin_rebuild() {
  if command -v darwin-rebuild >/dev/null 2>&1; then
    command -v darwin-rebuild
    return
  fi
  local candidate
  for candidate in \
    /run/current-system/sw/bin/darwin-rebuild \
    /nix/var/nix/profiles/system/sw/bin/darwin-rebuild
  do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  return 1
}

if ! DARWIN_REBUILD="$(find_darwin_rebuild)"; then
  echo "darwin-rebuild not found. Finish the first install with ./bootstrap.sh" >&2
  exit 1
fi

exec sudo "$DARWIN_REBUILD" switch --flake ~/.dotfiles#mac
