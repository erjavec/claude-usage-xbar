# claude-usage-xbar

See your Claude Code rate limits (the 5-hour and weekly windows) for every claude.ai account you use, right in the macOS menu bar. Switch Claude Code between those accounts with one command, without `/login`.

Two scripts:

- **`claude-usage.2m.sh`**: an [xbar](https://xbarapp.com) plugin. It shows the active account's 5-hour usage in the menu bar. The dropdown shows every saved account's windows with reset countdowns, plus today's token and cost totals from [ccusage](https://github.com/ryoppippi/ccusage).
- **`cswitch`**: saves each claude.ai login under a label and swaps between them. Only the login changes. Memory, settings, skills and history in `~/.claude` stay shared.

Unofficial, and not affiliated with Anthropic. Works on macOS only.

```
⏣ W 42%                          ← menu bar: active account's initial + its 5-hour usage
──────────────────────────────
Rate-limit windows
● work (active)
Acme Inc
as of 14:05
5-hour:  42%  ████░░░░░░
resets in 2h 10m
7-day:   18%  ██░░░░░░░░
resets in 4d 6h
──────────────────────────────
○ personal
personal org
as of 14:01
5-hour:  76%  ████████░░
resets in 1h 45m
7-day:   93%  █████████░
resets in 11h 20m
Switch to personal
──────────────────────────────
Tokens / cost (ccusage, all accounts)
Today:  $12.40 · 18.30M tokens
This block:  $8.15 · $3.20/hr
~$14.60 projected by reset
```

The bars are green below 70%, orange from 70% and red from 90%. A `*` after the menu-bar number means the last call failed and you're seeing the last good reading. A `!` means the Keychain login doesn't match the active account (see [Troubleshooting](#troubleshooting)).

## Requirements

- macOS, with Claude Code signed in to a claude.ai plan (Pro, Max, Team or Enterprise). API-key logins have no rate-limit windows.
- [xbar](https://xbarapp.com): `brew install --cask xbar`
- `jq` (included in macOS 15 and later, otherwise `brew install jq`) and `curl`
- Optional: [ccusage](https://github.com/ryoppippi/ccusage) for the token and cost section: `npm i -g ccusage`

## Install

```sh
git clone https://github.com/erjavec/claude-usage-xbar.git ~/Developer/claude-usage-xbar
cd ~/Developer/claude-usage-xbar
./install.sh
```

The installer checks the requirements. It then symlinks `cswitch` into `~/.local/bin` and the plugin into xbar's plugin folder, so a later `git pull` updates both. Use `./install.sh --copy` to copy the files instead. If a different version is already installed, the installer moves it to `~/.cache/claude-usage-xbar/backup` first.

Then save each account you use:

```sh
# Claude Code is signed in to your work account
cswitch save work

# in Claude Code: /login to your personal account, then
cswitch save personal
```

Labels can use lowercase letters, digits, `-` and `_`. The first letter of the active label appears in the menu bar. With only one account you can skip cswitch: the plugin still shows the active login, under the label `live`.

## Using cswitch

```
cswitch                 list saved accounts (* = active)
cswitch save <label>    save the current login under <label>
cswitch <label>         switch to <label> (current login is re-saved first)
cswitch current         print the active label (empty if the login is not saved)
```

You can also switch from the menu with **Switch to &lt;label&gt;**. A notification confirms the switch.

**Restart running Claude Code sessions after a switch.** A session that is still running on the old account can write its refreshed token back to the Keychain. cswitch reports how many sessions are running. If it happens anyway, the menu shows `!`. To fix it, restart the sessions and run `cswitch <label>` again.

## How it works

- The windows come from `https://api.anthropic.com/api/oauth/usage`, an undocumented endpoint that may change without notice. The endpoint returns HTTP 429 if it is polled too often, so the plugin calls it at most once every 10 minutes per account. xbar runs the plugin every 2 minutes; in between, it reads the cache in `~/.cache/claude-usage/` and recomputes the countdowns locally. **Force-update windows now** clears that cache.
- Accounts you're not using are read with their saved access token while it's still valid. Once it expires, the menu shows the last reading until you switch to that account again.
- Tokens are sent only to `api.anthropic.com`. The scripts pass them through pipes, never as command-line arguments, so other processes can't see them.

What gets stored:

| Where | What |
|---|---|
| Keychain item `Claude Code-credentials` | the active login (Claude Code's own item, which cswitch swaps) |
| Keychain items `Claude Code-credentials (cswitch)` | one saved login per label |
| `~/.claude-accounts/<label>.oauth.json` | the `oauthAccount` block from `~/.claude.json` (email, organization) |
| `~/.cache/claude-usage/<label>.cache` | the last rate-limit reading for each account |

## Troubleshooting

| You see | Meaning and fix |
|---|---|
| A blank item with only xbar's own menu | Blank for about 20 seconds after a refresh is normal, while the first run finishes (`ccusage` is slow). If it stays blank, xbar 2.1.7-beta has stopped showing its plugins, which can happen after several refreshes in a row. Quit and reopen xbar. |
| `⏣ ⚠︎` in the menu bar | Claude Code has no login in the Keychain. Sign in with Claude Code, then click **Refresh**. |
| `!` after the percentage | A running session wrote back the old account's token. Restart Claude Code sessions, then run `cswitch <label>`. |
| `*` after the percentage | The endpoint is rate-limiting (usually HTTP 429). The last good reading is shown and updates on its own. |
| "this login is not saved" | Run `cswitch save <label>` for the current login. |
| "saved token expired; switch to it once" | That account's saved access token has expired. Switch to it once to refresh it. |
| "ccusage not installed" when it is | xbar doesn't load your shell profile. Symlink it where xbar can find it: `ln -s "$(command -v ccusage)" ~/.local/bin/ccusage` |

## Uninstall

```sh
./install.sh --uninstall
```

This removes the script and the plugin but keeps your saved logins. The uninstaller prints the commands that delete them too.

## Contributing

Issues and pull requests are welcome. The scripts must run on macOS's built-in `/bin/bash` 3.2 and pass `shellcheck`, which CI checks on every push.

## License

[MIT](LICENSE)
