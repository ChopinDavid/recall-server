# recall-server

One-line setup for a personal [Anki](https://apps.ankiweb.net/) sync server —
the self-hosting companion to
[Recall](https://github.com/ChopinDavid/recall-lightos), and usable by any
Anki self-hoster (AnkiDroid, desktop-to-desktop, anything that speaks Anki's
sync protocol).

```sh
curl -fsSL https://raw.githubusercontent.com/ChopinDavid/recall-server/main/setup-server.sh | sh
```

That downloads a prebuilt `anki-sync-server` binary for your machine,
asks for a username and password, installs it to start at login (launchd on
macOS, systemd user unit on Linux), starts it, and prints the address,
username, and password to enter in your apps. Press Enter at either prompt
to accept the default: your computer's login name, and a random 16-character
password. Re-running upgrades in place and keeps your credentials and data.

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

## What the binaries are

Unmodified `anki-sync-server`, compiled by [this repo's CI](.github/workflows/build.yml)
from [ankitects/anki](https://github.com/ankitects/anki) at the tag named in
each release. No patches. Not affiliated with Anki/Ankitects.

## License

The binaries are built from Anki, which is **AGPL-3.0**; their complete
corresponding source is the pinned tag of ankitects/anki named in each
release. The setup script and workflow in this repo are MIT.
