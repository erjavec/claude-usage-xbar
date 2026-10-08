# claude-usage-xbar

Public repo: https://github.com/erjavec/claude-usage-xbar. On the maintainer's Mac the installed
copies are symlinks into this checkout (`~/.local/bin/cswitch`, `~/.local/bin/cping`,
`~/Library/Application Support/xbar/plugins/claude-usage.2m.sh`), so edits here go live right away.

- Target macOS `/bin/bash` 3.2: no associative arrays, `mapfile`, `${var,,}` or `|&`. Use BSD tool
  flags (`date -j`, `sed -i ''`).
- Never put tokens in argv or here-strings (bash 3.2 backs those with temp files). Pipe them, like
  `cj` and `kc_write` do.
- Before committing, run `shellcheck cswitch cping claude-usage.2m.sh install.sh`. CI runs the
  same check.
- For a user-visible change, bump `<xbar.version>` in the plugin and add a `CHANGELOG.md` entry.
- This repo is public: no real emails, org names, tokens or usage numbers in code, docs, test
  fixtures or commit messages.
