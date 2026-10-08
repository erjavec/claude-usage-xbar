# Changelog

## Unreleased

- `install.sh` refreshes xbar only when it installs into xbar's real plugin folder. Several refreshes in a row leave xbar 2.1.7-beta's plugins blank until it restarts, and test runs with `XBAR_PLUGIN_DIR` set used to cause exactly that.
- README: troubleshooting entry for blank menu items.

## 2.2.0 — 2026-10-08

First public release.

- Added `install.sh`, which symlinks or copies both scripts into place and can uninstall them.
- The plugin now finds `cswitch` and `ccusage` in common install locations (`~/.local/bin`, Homebrew on Apple silicon and Intel, Bun, Volta) instead of fixed paths.
- Added an xbar "about" link to this repo.
