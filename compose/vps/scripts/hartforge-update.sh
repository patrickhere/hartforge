#!/bin/bash
# HartForge MOTD auto-updater
# Pulls the latest MOTD script from Forgejo (primary) and installs it.
# Runs via cron every 6 hours.
# Needs FORGEJO_TOKEN in /opt/scripts/.env (repo is private).

ENV_FILE="/opt/scripts/.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

REPO_BASE="https://git.hartforge.dev/api/v1/repos/patrickhere/homelab-scripts/raw"

case "$(uname -s)" in
  Darwin) SCRIPT_PATH="motd/motd-macos.sh"; DEST="$HOME/.config/hartforge/motd.sh" ;;
  *)      SCRIPT_PATH="motd/motd-linux.sh"; DEST="/etc/profile.d/hartforge-motd.sh" ;;
esac

TMP=$(mktemp)
if curl -sf -H "Authorization: token ${FORGEJO_TOKEN}" -o "$TMP" "$REPO_BASE/$SCRIPT_PATH?ref=main"; then
  if ! diff -q "$TMP" "$DEST" &>/dev/null; then
    cp "$TMP" "$DEST"
    chmod +x "$DEST"
    logger "hartforge-motd: updated from git"
  fi
else
  logger "hartforge-motd: fetch failed"
fi
rm -f "$TMP"
