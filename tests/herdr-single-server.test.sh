#!/usr/bin/env bash
# A rebuild retargets ~/.dotfiles. Herdr's socket must stay put.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

home_nix=$(cat "$ROOT/home.nix")
assert_not_contains "$home_nix" 'home.file.".config/herdr".source' \
  "home.nix must not link the whole herdr directory through ~/.dotfiles"
assert_contains "$home_nix" 'home.file.".config/herdr/config.toml".source' \
  "home.nix must still link authored herdr config.toml"
assert_contains "$home_nix" 'home.file.".config/herdr/plugins/config".source' \
  "home.nix must still link authored herdr plugin config"
assert_contains "$home_nix" 'entryBefore [ "checkLinkTargets" ]' \
  "keepHerdrSocket must run before Home Manager's link collision check"
assert_contains "$home_nix" 'scripts/keep-herdr-socket.sh' \
  "keepHerdrSocket must call scripts/keep-herdr-socket.sh"
assert_contains "$home_nix" "https://herdr.dev/install.sh" \
  "a fresh machine must still install herdr"
assert_contains "$home_nix" 'herdr plugin install' \
  "a fresh machine must still install declared herdr plugins"
assert_not_contains "$home_nix" 'herdr server' \
  "activation must not start or stop a herdr server"

script="$ROOT/scripts/keep-herdr-socket.sh"
[[ -f "$script" ]] || fail "scripts/keep-herdr-socket.sh is missing"

pin_line=$(awk '/keep-herdr-socket\.sh/{print NR; exit}' "$ROOT/rebuild.sh")
ln_line=$(awk '/ln -sfn "\$DIR" ~\/\.dotfiles/{print NR; exit}' "$ROOT/rebuild.sh")
[[ -n "$pin_line" && -n "$ln_line" && "$pin_line" -lt "$ln_line" ]] \
  || fail "rebuild.sh must pin the herdr socket before it retargets ~/.dotfiles"

listener_pid=
finish() {
  if [[ -n "${listener_pid:-}" ]]; then
    kill "$listener_pid" 2>/dev/null || true
    wait "$listener_pid" 2>/dev/null || true
  fi
  # Command substitution runs the helper in a subshell, so its EXIT trap
  # never owns this directory.
  if [[ -n "${root:-}" ]]; then
    rm -rf "$root"
  fi
}

# macOS unix sockets reject paths longer than 104 bytes. The default temp
# directory under /var/folders is already most of that budget.
root=$(TMPDIR=/tmp dotfiles_test_tmproot hst)
trap finish EXIT
repo_a="$root/repo-a/home/.config/herdr"
repo_b="$root/repo-b/home/.config/herdr"
mkdir -p "$repo_a/plugins/github/demo" "$repo_a/session-backups" \
  "$repo_b/session-backups" "$root/home/.config" "$root/home/.dotfiles-parent"
printf 'session-a\n' > "$repo_a/session.json"
printf 'backup-a\n' > "$repo_a/session-backups/fleet"
printf 'plugin\n' > "$repo_a/plugins/github/demo/marker"
# The new checkout has different runtime files. A pin that runs after the
# retarget would copy these and miss the live socket.
printf 'session-b\n' > "$repo_b/session.json"
printf 'backup-b\n' > "$repo_b/session-backups/other"
ln -s "$root/repo-a" "$root/home/.dotfiles"
# Same chain as Home Manager: ~/.config/herdr -> store symlink -> ~/.dotfiles/...
ln -s "$root/home/.dotfiles/home/.config/herdr" "$root/store-herdr"
ln -s "$root/store-herdr" "$root/home/.config/herdr"

python3 - "$repo_a/herdr.sock" << 'PY' &
import socket, sys, time
path = sys.argv[1]
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(4)
srv.settimeout(0.2)
deadline = time.time() + 30
while time.time() < deadline:
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        continue
    conn.sendall(b"ok:" + conn.recv(8))
    conn.close()
srv.close()
PY
listener_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -S "$repo_a/herdr.sock" ]] && break
  sleep 0.05
done
[[ -S "$repo_a/herdr.sock" ]] || fail "fixture socket did not appear"

ping() {
  python3 - "$1" << 'PY'
import socket, sys
path = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(2)
s.connect(path)
s.sendall(b"Z")
data = s.recv(8)
s.close()
assert data == b"ok:Z", data
PY
}

ping "$root/home/.config/herdr/herdr.sock" \
  || fail "fixture socket was not reachable before the pin"

HOME="$root/home" bash "$script"
[[ -L "$root/home/.config/herdr" ]] || fail "pinned ~/.config/herdr must stay a symlink"
[[ "$(readlink "$root/home/.config/herdr")" == "$root/home/.local/herdr" ]] \
  || fail "pinned ~/.config/herdr must point at ~/.local/herdr"
[[ "$(stat -f %i "$root/home/.config/herdr/herdr.sock")" == "$(stat -f %i "$repo_a/herdr.sock")" ]] \
  || fail "pinned socket must be the same inode as the running server"
[[ "$(cat "$root/home/.local/herdr/session.json")" == "session-a" ]] \
  || fail "session.json must be copied from the old target"
[[ "$(cat "$root/home/.local/herdr/session-backups/fleet")" == "backup-a" ]] \
  || fail "session-backups must be copied from the old target"
[[ -f "$root/home/.local/herdr/plugins/github/demo/marker" ]] \
  || fail "installed plugins must be copied into the stable directory"
ping "$root/home/.config/herdr/herdr.sock" \
  || fail "pinned socket was not reachable"

# rebuild.sh order: pin, then retarget ~/.dotfiles, then activation runs the
# same script again. The second run must not pick up the new checkout.
ln -sfn "$root/repo-b" "$root/home/.dotfiles"
HOME="$root/home" bash "$script"
[[ "$(readlink "$root/home/.config/herdr")" == "$root/home/.local/herdr" ]] \
  || fail "activation after retarget must leave the pin in place"
[[ "$(cat "$root/home/.local/herdr/session.json")" == "session-a" ]] \
  || fail "activation after retarget must keep the old session.json"
[[ "$(cat "$root/home/.local/herdr/session-backups/fleet")" == "backup-a" ]] \
  || fail "activation after retarget must keep the old session-backups"
[[ ! -e "$root/home/.local/herdr/session-backups/other" ]] \
  || fail "activation after retarget must not import the new checkout's backups"
ping "$root/home/.config/herdr/herdr.sock" \
  || fail "retargeting ~/.dotfiles dropped the running socket"
[[ ! -S "$repo_b/herdr.sock" ]] || fail "retarget created a socket in the new repo"

# An already-real config directory is stable and must be left alone.
real_home="$root/real-home"
mkdir -p "$real_home/.config/herdr"
printf 'leave-me\n' > "$real_home/.config/herdr/session.json"
HOME="$real_home" bash "$script"
[[ ! -L "$real_home/.config/herdr" ]] || fail "a real ~/.config/herdr must not be replaced"
[[ "$(cat "$real_home/.config/herdr/session.json")" == "leave-me" ]] \
  || fail "a real ~/.config/herdr must keep its session file"
[[ ! -e "$real_home/.local/herdr" ]] || fail "a real ~/.config/herdr must not grow a second runtime dir"

# A machine with no herdr directory yet gets the stable pin, not a repo path.
fresh="$root/fresh"
mkdir -p "$fresh"
HOME="$fresh" bash "$script"
[[ -L "$fresh/.config/herdr" ]] || fail "a missing ~/.config/herdr must become a symlink"
[[ "$(readlink "$fresh/.config/herdr")" == "$fresh/.local/herdr" ]] \
  || fail "a missing ~/.config/herdr must point at ~/.local/herdr"
[[ -d "$fresh/.local/herdr" ]] || fail "the stable runtime directory must exist"

pass "herdr socket stays reachable when ~/.dotfiles is retargeted"
