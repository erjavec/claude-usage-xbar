#!/bin/bash
# install.sh — install cswitch and the Claude Usage xbar plugin from this checkout.
#
#   ./install.sh               symlink both into place (a later `git pull` updates them)
#   ./install.sh --copy        copy instead of symlinking (the checkout can be deleted afterwards)
#   ./install.sh --uninstall   remove them again (saved logins in the Keychain are kept)
#
# cswitch goes to ~/.local/bin, the plugin to xbar's plugin folder. Existing files that differ
# are moved to ~/.cache/claude-usage-xbar/backup first (not next to the plugin: xbar would run them).
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="${XBAR_PLUGIN_DIR:-$HOME/Library/Application Support/xbar/plugins}"
BACKUP_DIR="$HOME/.cache/claude-usage-xbar/backup"
PLUGIN=claude-usage.2m.sh

die(){ echo "install.sh: $*" >&2; exit 1; }
ok(){ echo "  ✓ $*"; }
warn(){ echo "  ! $*"; }

# put <src> at <dst> (symlink or copy); back up whatever different file was there before
place(){ local src=$1 dst=$2 mode=$3 bak
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    [ "$mode" = link ] && { ok "$dst (already linked)"; return; }
    rm -f "$dst"                                          # our own link: nothing to keep
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -L "$dst" ] || ! cmp -s "$src" "$dst"; then
      mkdir -p "$BACKUP_DIR"; bak="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d-%H%M%S)-$$"
      mv "$dst" "$bak"; warn "moved the previous $(basename "$dst") to $bak"
    fi
    rm -f "$dst"
  fi
  if [ "$mode" = link ]; then ln -s "$src" "$dst"; else cp "$src" "$dst"; chmod +x "$dst"; fi
  ok "$dst"; }

# remove <dst> if it is our symlink or an unmodified copy
unplace(){ local src=$1 dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then rm -f "$dst"; ok "removed $dst"
  elif [ -f "$dst" ] && cmp -s "$src" "$dst"; then rm -f "$dst"; ok "removed $dst"
  elif [ -e "$dst" ]; then warn "left $dst alone (not installed from this checkout or modified)"
  fi; }

[ "$(uname -s)" = Darwin ] || die "macOS only (logins are stored in the macOS Keychain)"

MODE="link"
case "${1:-}" in
  "") ;;
  --copy) MODE=copy ;;
  --uninstall)
    echo "Uninstalling"
    unplace "$REPO/cswitch" "$BIN_DIR/cswitch"
    unplace "$REPO/$PLUGIN" "$PLUGIN_DIR/$PLUGIN"
    pgrep -qx xbar && open -g "xbar://app.xbarapp.com/refreshAllPlugins" 2>/dev/null || true
    cat <<EOF

Saved logins were kept. To remove them as well:
  for l in \$(ls ~/.claude-accounts | sed -n 's/\.oauth\.json\$//p'); do
    security delete-generic-password -s "Claude Code-credentials (cswitch)" -a "\$l"
  done
  rm -rf ~/.claude-accounts ~/.cache/claude-usage
EOF
    exit 0 ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown option '$1' (see --help)" ;;
esac

echo "Checking requirements"
missing=0
for c in jq curl xxd security; do
  if command -v "$c" >/dev/null; then ok "$c"; else warn "$c not found"; missing=1; fi
done
[ "$missing" = 0 ] || die "install the missing tools above, then rerun"
if [ -d /Applications/xbar.app ] || [ -d "$HOME/Applications/xbar.app" ]; then ok "xbar"
else warn "xbar not found — install it: brew install --cask xbar"; fi
# xbar does not read your shell profile: look where the plugin's PATH looks
CCU=$(PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.bun/bin:$HOME/.volta/bin:/usr/bin:/bin" command -v ccusage || true)
if [ -n "$CCU" ]; then ok "ccusage (optional)"
elif command -v ccusage >/dev/null; then
  warn "ccusage is at $(command -v ccusage), which xbar can't see — symlink it into ~/.local/bin for the cost section"
else warn "ccusage not found (optional, for the cost section): npm i -g ccusage"; fi
command -v claude >/dev/null || warn "claude (Claude Code) not found on PATH"

echo "Installing ($MODE)"
mkdir -p "$BIN_DIR" "$PLUGIN_DIR"
chmod +x "$REPO/cswitch" "$REPO/$PLUGIN"
place "$REPO/cswitch" "$BIN_DIR/cswitch" "$MODE"
place "$REPO/$PLUGIN" "$PLUGIN_DIR/$PLUGIN" "$MODE"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not on your PATH — add it to your shell profile" ;; esac
pgrep -qx xbar && open -g "xbar://app.xbarapp.com/refreshAllPlugins" 2>/dev/null || true

cat <<EOF

Done. Next, save each claude.ai account you use with Claude Code:
  1. In Claude Code, sign in to the first account (/login), then:   cswitch save work
  2. /login to the next account, then:                               cswitch save personal
  3. Switch any time with:  cswitch work   (or from the xbar menu)
Labels are free-form: lowercase letters, digits, - and _.
EOF
