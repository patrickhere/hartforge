#!/bin/bash
# Reminds on any still-down Uptime Kuma monitors, every 2 days at noon.
# Kuma's own resend_interval only counts check-cycles, not wall-clock time,
# so a fixed-time reminder needs to live outside it. Runs against the local
# (VPS) Kuma instance since it stays reachable even during LAN-side outages.

NTFY_URL="https://ntfy.hartforge.dev/homelab-alerts"
KUMA_DB="/var/lib/docker/volumes/uptime-kuma_data/_data/kuma.db"

source /opt/scripts/.env 2>/dev/null

DOWN=$(sqlite3 "$KUMA_DB" "
  SELECT m.name FROM monitor m
  WHERE m.active = 1
  AND (SELECT status FROM heartbeat WHERE monitor_id = m.id ORDER BY time DESC LIMIT 1) = 0
")

if [ -n "$DOWN" ]; then
  MSG=$(echo "$DOWN" | sed 's/^/- /')
  curl -s -u "${NTFY_USER}:${NTFY_PASS}" \
    -H "Title: Uptime Kuma - Still Down" \
    -H "Priority: default" \
    -H "Tags: warning" \
    -H "Actions: view, Open Uptime Kuma, https://uptime-ext.hartforge.dev" \
    -d "$MSG" \
    "$NTFY_URL" > /dev/null 2>&1
fi
