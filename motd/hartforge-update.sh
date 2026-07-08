#!/bin/bash
# HartForge MOTD auto-updater
# Pulls the latest MOTD script from Forgejo and installs it.
# Runs via cron every 6 hours.

REPO_BASE="http://10.1.0.56:3000/patrickhere/homelab-scripts/raw/branch/main/motd"

case "$(uname -s)" in
  Darwin) SCRIPT_URL="$REPO_BASE/motd-macos.sh"; DEST="$HOME/.config/hartforge/motd.sh" ;;
  *)      SCRIPT_URL="$REPO_BASE/motd-linux.sh"; DEST="/etc/profile.d/hartforge-motd.sh" ;;
esac

TMP=$(mktemp)
if curl -sf -o "$TMP" "$SCRIPT_URL"; then
  if ! diff -q "$TMP" "$DEST" &>/dev/null; then
    cp "$TMP" "$DEST"
    chmod +x "$DEST"
    logger "hartforge-motd: updated from git"
  fi
fi
rm -f "$TMP"
