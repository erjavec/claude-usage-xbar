# Changelog

## Unreleased

- The plugin no longer flashes the "Keychain holds a … login" warning (or briefly shows the wrong account as active) when a refresh lands in the middle of a `cswitch` switch. It now looks again after 3 seconds and warns only if the mismatch is still there.
- The mismatch warning now also names the Claude desktop app as a possible cause. Its login is written to `~/.claude.json`, so having the app on a different account than the CLI triggers the warning.

## 2.3.0 — 2026-10-08

- Added `cping`, which opens the active login's 5-hour window at fixed hours (`cping schedule 4 9 14 19`) so the windows line up with your day. It sends one tiny Haiku request through Claude Code from a launchd agent, and skips a ping that runs late because the Mac was asleep. `install.sh` installs it, and `--uninstall` also removes its schedule.
- `install.sh` refreshes xbar only when it installs into xbar's real plugin folder. Several refreshes in a row leave xbar 2.1.7-beta's plugins blank until it restarts, and test runs with `XBAR_PLUGIN_DIR` set used to cause exactly that.
- README: troubleshooting entry for blank menu items.

## 2.2.0 — 2026-10-08

First public release.

- Added `install.sh`, which symlinks or copies both scripts into place and can uninstall them.
- The plugin now finds `cswitch` and `ccusage` in common install locations (`~/.local/bin`, Homebrew on Apple silicon and Intel, Bun, Volta) instead of fixed paths.
- Added an xbar "about" link to this repo.
