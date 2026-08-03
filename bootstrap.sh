#!/usr/bin/env bash
# Takes a fresh Mac from nothing to a built nix-darwin config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 1: install Nix"
# Determinate Nix dropped x86_64-darwin (Intel Mac) support in late 2025.
# Apple Silicon still uses Determinate; Intel uses the official multi-user installer.
#
# Fresh official-Nix installs only put `nix` on PATH for *new* shells. An
# in-progress bootstrap (or a re-run after a partial install) often has the
# binary under /nix but not on PATH yet — treat that as "already installed"
# and source the daemon profile instead of re-running the installer (which
# fails on leftover /etc/*.backup-before-nix files).
ensure_nix_on_path() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi
  # shellcheck disable=SC1091
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1
}

if ensure_nix_on_path; then
  echo "    nix already installed ($(command -v nix)), skipping installer"
else
  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64|aarch64)
      echo "    Apple Silicon: Determinate Nix"
      curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
        | sh -s -- install --no-confirm
      ;;
    x86_64)
      echo "    Intel Mac: official Nix (Determinate no longer ships x86_64-darwin)"
      curl --proto '=https' --tlsv1.2 -sSf -L https://nixos.org/nix/install \
        | sh -s -- --daemon --yes
      ;;
    *)
      echo "    Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  if ! command -v nix >/dev/null 2>&1; then
    echo "    nix installed but not on PATH in this shell."
    echo "    Open a new terminal and re-run ./bootstrap.sh"
    exit 1
  fi
fi

# Official Nix does not enable flakes by default; Determinate does.
# The first-switch step below needs flakes either way.
# Write the user conf so interactive `nix` works, and also ensure the
# system conf has the features: Step 4 runs under sudo, which does not
# read ~/.config/nix/nix.conf (root's HOME is /var/root).
enable_experimental_features() {
  local conf="$1"
  local dir
  dir="$(dirname "$conf")"
  mkdir -p "$dir"
  if [ -f "$conf" ] && grep -q '^experimental-features' "$conf"; then
    # Leave an existing line alone if something custom is already set.
    :
  else
    printf 'experimental-features = nix-command flakes\n' >> "$conf"
  fi
}

if ! nix show-config 2>/dev/null | grep -q 'experimental-features.*flakes'; then
  echo "    enabling nix-command and flakes in ~/.config/nix/nix.conf"
  enable_experimental_features "$HOME/.config/nix/nix.conf"
fi
# Always make sure sudo/system nix can use nix-command + flakes for Step 4.
# After the first successful switch, nix-darwin manages /etc/nix/nix.conf.
if [ -f /etc/nix/nix.conf ] && ! grep -q '^experimental-features' /etc/nix/nix.conf; then
  echo "    enabling nix-command and flakes in /etc/nix/nix.conf (needed for sudo nix)"
  # Append via sudo; do not replace the installer-managed file.
  printf 'experimental-features = nix-command flakes\n' | sudo tee -a /etc/nix/nix.conf >/dev/null
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
# Do this before any sudo call: sudo resets $USER to root, so whoami has to
# run as the real interactive user first.
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: hand /etc files from the Nix installer over to nix-darwin"
# First activation aborts if these still have installer-written content.
# Renaming with the required suffix lets nix-darwin replace them safely.
# Contents are only the stock Nix multi-user hooks + nix.conf; nothing custom.
for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
  if [ -e "$f" ] && [ ! -e "${f}.before-nix-darwin" ]; then
    echo "    mv $f -> ${f}.before-nix-darwin"
    sudo mv "$f" "${f}.before-nix-darwin"
  elif [ -e "${f}.before-nix-darwin" ]; then
    echo "    already set aside: ${f}.before-nix-darwin"
  else
    echo "    $f not present (ok)"
  fi
done

echo "==> Step 5: restore Nix volume mount config if missing"
# Official installer may have removed these during a failed re-install
# (no-TTY assumes "yes" to cleanup prompts). Without them:
# - nix-darwin activation fails chmod'ing /etc/synthetic.conf
# - /nix may not remount after reboot
if ! [ -f /etc/synthetic.conf ] || ! grep -qE '^nix($|[[:space:]])' /etc/synthetic.conf 2>/dev/null; then
  echo "    writing /etc/synthetic.conf (nix mount point)"
  printf 'nix\n' | sudo tee /etc/synthetic.conf >/dev/null
else
  echo "    /etc/synthetic.conf ok"
fi

# Detect the APFS "Nix Store" volume UUID when present (Intel multi-user layout).
NIX_VOL_UUID="$(diskutil info "Nix Store" 2>/dev/null | awk -F': *' '/Volume UUID/ {print $2; exit}')"
if [ -n "$NIX_VOL_UUID" ]; then
  if ! [ -f /etc/fstab ] || ! grep -q '/nix apfs rw' /etc/fstab 2>/dev/null; then
    echo "    writing /etc/fstab mount options for Nix Store ($NIX_VOL_UUID)"
    printf 'UUID=%s /nix apfs rw,noauto,nobrowse,nosuid,noatime,owners\n' "$NIX_VOL_UUID" \
      | sudo tee /etc/fstab >/dev/null
  else
    echo "    /etc/fstab ok"
  fi

  DARWIN_STORE_PLIST=/Library/LaunchDaemons/org.nixos.darwin-store.plist
  if [ ! -f "$DARWIN_STORE_PLIST" ]; then
    echo "    installing org.nixos.darwin-store LaunchDaemon"
    # Encrypted volumes (FileVault) unlock via keychain; unencrypted just mount.
    if diskutil apfs listCryptoUsers "$(diskutil info "Nix Store" | awk -F': *' '/Device Node/ {print $2; exit}')" 2>/dev/null \
        | grep -q 'Cryptographic user'; then
      MOUNT_CMD="/usr/bin/security find-generic-password -s '$NIX_VOL_UUID' -w | /usr/sbin/diskutil apfs unlockVolume '$NIX_VOL_UUID' -mountpoint '/nix' -stdinpassphrase"
    else
      MOUNT_CMD="/usr/sbin/diskutil mount -mountPoint /nix $NIX_VOL_UUID"
    fi
    sudo tee "$DARWIN_STORE_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>RunAtLoad</key>
  <true/>
  <key>Label</key>
  <string>org.nixos.darwin-store</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>${MOUNT_CMD}</string>
  </array>
</dict>
</plist>
EOF
    sudo launchctl bootstrap system "$DARWIN_STORE_PLIST" 2>/dev/null || true
    sudo launchctl kickstart -k system/org.nixos.darwin-store 2>/dev/null || true
  else
    echo "    $DARWIN_STORE_PLIST ok"
  fi
else
  echo "    no separate Nix Store volume (ok for Determinate / single-volume installs)"
fi

echo "==> Step 6: first darwin-rebuild switch (pinned to nix-darwin-26.05)"
# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
# from the flake this once. After this, rebuild.sh works normally.
# This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
# not the exact flake.lock revision. The system config it applies is still pinned
# by this repo's flake.lock.
# sudo resets PATH to a secure default that excludes /nix/.../bin, so a
# freshly installed `nix` would not be found under sudo even though it's
# on PATH here. Resolve the absolute path first and invoke that instead.
NIX_BIN="$(command -v nix)"
# "mac" is the flake host label - if you renamed it, change it in flake.nix
# and rebuild.sh too.
# Pass --extra-experimental-features as a belt-and-suspenders for shells
# where /etc/nix/nix.conf was not updated yet (or nix-daemon still has the
# old config). `nix run` needs nix-command; flakes need flakes.
sudo "$NIX_BIN" --extra-experimental-features 'nix-command flakes' \
  run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake ~/.dotfiles#mac
# If this still fails with "nix: command not found", open a new terminal
# (the installer adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Done. Use ./rebuild.sh for future changes."
