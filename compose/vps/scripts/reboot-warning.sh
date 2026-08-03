#!/usr/bin/env bash
# evening heads-up when unattended-upgrades has queued a reboot (happens 09:30 UTC)
set -euo pipefail
source /opt/scripts/.env

if [ -f /var/run/reboot-required ]; then
    PKGS=$(cat /var/run/reboot-required.pkgs 2>/dev/null | sort -u | tr '\n' ' ')
    /opt/scripts/notify.sh -t alerts -T "VPS reboots at 09:30 UTC" -g arrows_counterclockwise \
        -- "kernel/libc update queued: ${PKGS:-see reboot-required}. auto-reboot happens at 09:30 UTC (~3:30am central), stack self-assembles on boot." >/dev/null
fi
