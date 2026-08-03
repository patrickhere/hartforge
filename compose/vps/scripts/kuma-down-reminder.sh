#!/bin/bash
# Reminds on any still-down Uptime Kuma monitors, every 2 days at noon.
# Kuma's own resend_interval only counts check-cycles, not wall-clock time,
# so a fixed-time reminder needs to live outside it. Runs against the local
# (VPS) Kuma instance since it stays reachable even during LAN-side outages.

KUMA_DB="/var/lib/docker/volumes/uptime-kuma_data/_data/kuma.db"

source /opt/scripts/.env 2>/dev/null

DOWN=$(sqlite3 "$KUMA_DB" "
  SELECT m.name FROM monitor m
  WHERE m.active = 1
  AND (SELECT status FROM heartbeat WHERE monitor_id = m.id ORDER BY time DESC LIMIT 1) = 0
")

if [ -n "$DOWN" ]; then
  MSG=$(echo "$DOWN" | sed 's/^/- /')
  # $MSG lines start with "- ", so -- before the body is load-bearing:
  # getopts would otherwise eat the first line as a flag and send nothing.
  /opt/scripts/notify.sh -t alerts -T "Uptime Kuma - Still Down" -g warning \
    -c "https://uptime-ext.hartforge.dev" \
    -- "$MSG" > /dev/null 2>&1
fi
