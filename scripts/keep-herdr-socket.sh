#!/usr/bin/env bash
# Pin Herdr's runtime directory off ~/.dotfiles.
#
# Herdr 0.9.1 binds $HOME/.config/herdr/herdr.sock (or $XDG_CONFIG_HOME/herdr).
# There is no config.toml key for that path. rebuild.sh replaces ~/.dotfiles
# with `ln -sfn` on every run. When the whole config directory is an
# out-of-store symlink through ~/.dotfiles, that replacement moves the socket
# path out from under the running server, and the next `herdr server` binds a
# fresh empty one.
#
# rebuild.sh must run this before `ln -sfn ~/.dotfiles`. After that ln,
# realpath(~/.config/herdr) is the new checkout and the live socket is no
# longer visible. Home Manager activation runs it again; once pinned, that
# second run is a no-op. A live socket is hardlinked into ~/.local/herdr
# before the symlink is swapped, and session.json plus session-backups are
# copied from the directory the socket still resolves to.
set -euo pipefail

config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
herdr_home="${config_root}/herdr"
stable="${HOME}/.local/herdr"

if [[ -e "$herdr_home" && ! -L "$herdr_home" ]]; then
  exit 0
fi

if [[ -L "$herdr_home" && "$(readlink "$herdr_home")" == "$stable" ]]; then
  exit 0
fi

mkdir -p "$stable"
mkdir -p "$(dirname "$herdr_home")"

if [[ -L "$herdr_home" ]]; then
  real=""
  if ! real="$(realpath "$herdr_home" 2>/dev/null)"; then
    real=""
  fi
  if [[ -n "$real" && "$real" != "$stable" ]]; then
    for name in herdr.sock herdr-client.sock; do
      if [[ -S "$real/$name" && ! -e "$stable/$name" ]]; then
        ln "$real/$name" "$stable/$name" \
          || ln -s "$real/$name" "$stable/$name"
      fi
    done
    for name in session.json plugins.json .plugins.lock session-history.json; do
      if [[ -f "$real/$name" && ! -e "$stable/$name" ]]; then
        cp -p "$real/$name" "$stable/$name"
      fi
    done
    if [[ -d "$real/session-backups" && ! -e "$stable/session-backups" ]]; then
      cp -a "$real/session-backups" "$stable/session-backups"
    fi
    if [[ -d "$real/plugins/github" && ! -e "$stable/plugins/github" ]]; then
      mkdir -p "$stable/plugins"
      cp -a "$real/plugins/github" "$stable/plugins/"
    fi
  fi

  link_tmp="$(mktemp "${config_root}/.herdr-link.XXXXXX")"
  rm -f "$link_tmp"
  ln -s "$stable" "$link_tmp"
  # BSD mv follows a symlink-to-directory and would drop the new link inside
  # the old config dir. rename(2) replaces the symlink itself.
  /usr/bin/python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
    "$link_tmp" "$herdr_home"
  echo "keep-herdr-socket: pinned ${herdr_home} at ${stable}" >&2
  exit 0
fi

ln -s "$stable" "$herdr_home"
echo "keep-herdr-socket: pinned ${herdr_home} at ${stable}" >&2
