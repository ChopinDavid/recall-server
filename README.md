# recall-server

One-line setup for a personal [Anki](https://apps.ankiweb.net/) sync server —
the self-hosting companion to
[Recall](https://github.com/ChopinDavid/recall-lightos), and usable by any
Anki self-hoster (AnkiDroid, desktop-to-desktop, anything that speaks Anki's
sync protocol).

**macOS / Linux** — paste into the Terminal app:

```sh
curl -fsSL https://raw.githubusercontent.com/ChopinDavid/recall-server/main/setup-server.sh | sh
```

**Windows** — paste into Command Prompt or PowerShell:

```bat
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/ChopinDavid/recall-server/main/setup-server.ps1 | iex"
```

Either one downloads a prebuilt `anki-sync-server` binary for your machine,
asks for a username and password, installs it to start at login, starts it,
and prints the address, username, and password to enter in your apps. Press
Enter at either prompt to accept the default: your computer's login name,
and a random 16-character password. Re-running upgrades in place and keeps
your credentials and data.

On Windows, the script also asks once for administrator permission to let
the server through Windows Firewall (on private networks only), so your
phone can reach it. `-ExecutionPolicy Bypass` applies to that one command
only; it doesn't change any setting.

### macOS / Linux details

- Runs as a launchd agent (macOS) or systemd user unit (Linux).
- Data: `~/.recall-server/data` — back it up like any Anki data.
- Log: `~/.recall-server/server.log`
- Change the port: `RECALL_SERVER_PORT=27701 sh setup-server.sh`
- Set credentials without prompts (first run only):
  `RECALL_SERVER_USER=alice RECALL_SERVER_PASSWORD=... sh setup-server.sh`.
  With no terminal attached (CI, provisioning), the script skips the prompts
  and uses these or the defaults.
- Change credentials later: edit `SYNC_USER1=` in
  `~/.recall-server/server-env`, or delete that file and re-run. Data is
  stored per username, so a new username starts empty until you sync from
  Anki desktop.
- Uninstall: remove `~/.recall-server` and the
  `com.recall.anki-sync-server` LaunchAgent / `recall-anki-sync-server`
  systemd unit.

### Windows details

- Starts at login from a `recall-server` shortcut in your Startup folder
  (in a hidden window, no administrator rights needed) and restarts the
  server if it stops.
- Data: `%USERPROFILE%\.recall-server\data` — back it up like any Anki data.
- Log: `%USERPROFILE%\.recall-server\server.log`
- Change the port or set credentials without prompts: set
  `RECALL_SERVER_PORT`, `RECALL_SERVER_USER` and `RECALL_SERVER_PASSWORD`
  first (in Command Prompt: `set RECALL_SERVER_PORT=27701`).
- Change credentials later: edit `SYNC_USER1=` in
  `%USERPROFILE%\.recall-server\server-env`, or delete that file and re-run.
- If your phone can't connect, check that Windows treats your network as
  **Private** (Settings → Network & internet); the script warns when it's
  Public.
- Uninstall: delete `recall-server` from your Startup folder (Win+R,
  `shell:startup`), sign out and back in (or end `anki-sync-server` in Task
  Manager), delete `%USERPROFILE%\.recall-server`, and remove the firewall
  rule in PowerShell as administrator:
  `Remove-NetFirewallRule -DisplayName 'recall-server (Anki sync)'`.

## What the binaries are

Unmodified `anki-sync-server`, compiled by [this repo's CI](.github/workflows/build.yml)
from [ankitects/anki](https://github.com/ankitects/anki) at the tag named in
each release. No patches. Not affiliated with Anki/Ankitects.

## License

The binaries are built from Anki, which is **AGPL-3.0**; their complete
corresponding source is the pinned tag of ankitects/anki named in each
release. The setup script and workflow in this repo are MIT.
