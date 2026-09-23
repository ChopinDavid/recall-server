#!/bin/sh
# recall-server setup — puts a personal Anki sync server on this computer.
#
#   curl -fsSL https://raw.githubusercontent.com/ChopinDavid/recall-server/main/setup-server.sh | sh
#
# What it does, in order:
#   1. Downloads the anki-sync-server binary for this machine (from this
#      repo's GitHub Releases; built by CI from ankitects/anki, AGPL-3.0).
#   2. Generates a username/password (or keeps your existing ones).
#   3. Installs a launchd agent (macOS) or systemd user unit (Linux) so the
#      server starts at login and restarts if it stops.
#   4. Prints the address + credentials to enter in Recall and Anki desktop.
#
# Re-running is safe: it upgrades the binary and keeps credentials + data.
# Data lives in ~/.recall-server/data — back it up like any Anki data.
set -eu

REPO="ChopinDavid/recall-server"
HOME_DIR="${HOME}/.recall-server"
BIN="${HOME_DIR}/anki-sync-server"
ENV_FILE="${HOME_DIR}/server-env"
DATA_DIR="${HOME_DIR}/data"
PORT="${RECALL_SERVER_PORT:-8080}"

say() { printf '%s\n' "$*"; }
fail() { say "setup-server: $*" >&2; exit 1; }

# ---- 1. platform + latest release asset -----------------------------------
OS=$(uname -s); ARCH=$(uname -m)
case "$OS-$ARCH" in
  Darwin-arm64)  ASSET="anki-sync-server-macos-arm64" ;;
  Darwin-x86_64) ASSET="anki-sync-server-macos-x86_64" ;;
  Linux-x86_64)  ASSET="anki-sync-server-linux-x86_64" ;;
  Linux-aarch64) ASSET="anki-sync-server-linux-arm64" ;;
  *) fail "no prebuilt binary for $OS/$ARCH yet — see the README's manual (venv) instructions." ;;
esac

mkdir -p "$HOME_DIR" "$DATA_DIR"
say "Downloading the sync server (${ASSET})..."
URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
curl -fSL --progress-bar -o "${BIN}.tmp" "$URL" || fail "download failed: $URL"
mv "${BIN}.tmp" "$BIN"; chmod +x "$BIN"

# ---- 2. credentials (kept across re-runs) ---------------------------------
if [ -f "$ENV_FILE" ]; then
  say "Keeping your existing username/password."
else
  USER_NAME="${USER:-anki}"
  PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
  {
    echo "SYNC_USER1=${USER_NAME}:${PASS}"
    echo "SYNC_BASE=${DATA_DIR}"
    echo "SYNC_HOST=0.0.0.0"
    echo "SYNC_PORT=${PORT}"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi
# shellcheck disable=SC1090
. "$ENV_FILE"
CREDS_USER=${SYNC_USER1%%:*}; CREDS_PASS=${SYNC_USER1#*:}

# ---- 3. run at login, restart on crash ------------------------------------
RUNNER="${HOME_DIR}/run-server.sh"
{
  echo '#!/bin/sh'
  echo "set -a; . '${ENV_FILE}'; set +a"
  echo "exec '${BIN}' >> '${HOME_DIR}/server.log' 2>&1"
} > "$RUNNER"; chmod +x "$RUNNER"

if [ "$OS" = "Darwin" ]; then
  PLIST="${HOME}/Library/LaunchAgents/com.recall.anki-sync-server.plist"
  mkdir -p "${HOME}/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.recall.anki-sync-server</string>
  <key>ProgramArguments</key><array><string>${RUNNER}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
else
  UNIT_DIR="${HOME}/.config/systemd/user"; mkdir -p "$UNIT_DIR"
  cat > "${UNIT_DIR}/recall-anki-sync-server.service" <<EOF
[Unit]
Description=Personal Anki sync server (recall-server)
[Service]
ExecStart=${RUNNER}
Restart=always
[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now recall-anki-sync-server.service
fi

# ---- 4. verify + print the card -------------------------------------------
sleep 2
ADDR=""
if [ "$OS" = "Darwin" ]; then
  ADDR=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
else
  ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -n "$ADDR" ] || ADDR="<your computer's local address>"

if curl -fs -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null || [ "$?" = "22" ]; then
  RUNNING="yes"
else
  RUNNING="maybe"
fi

say ""
say "==============================================================="
say " Your Anki sync server is set up."
say ""
say "   In Recall on your phone:"
say "     Sync endpoint:  http://${ADDR}:${PORT}/"
say "     Username:       ${CREDS_USER}"
say "     Password:       ${CREDS_PASS}"
say ""
say "   In Anki on this computer (Preferences -> Syncing):"
say "     Self-hosted sync server:  http://localhost:${PORT}/"
say "     Then restart Anki, press Sync, and choose Upload."
say ""
say "   It starts automatically when you log in."
say "   Data: ${DATA_DIR}    Log: ${HOME_DIR}/server.log"
[ "$RUNNING" = "yes" ] || say "   NOTE: could not confirm the server answered yet; check the log."
say "==============================================================="
