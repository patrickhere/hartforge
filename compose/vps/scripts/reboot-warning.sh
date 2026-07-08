#!/usr/bin/env bash
# evening heads-up when unattended-upgrades has queued a reboot (happens 05:30)
set -euo pipefail
source /opt/scripts/.env

if [ -f /var/run/reboot-required ]; then
    PKGS=$(cat /var/run/reboot-required.pkgs 2>/dev/null | sort -u | tr '\n' ' ')
    curl -fsS -m 10 -u "$NTFY_USER:$NTFY_PASS" \
        -H "Title: VPS reboots at 05:30" \
        -H "Tags: arrows_counterclockwise" \
        -d "kernel/libc update queued: ${PKGS:-see reboot-required}. auto-reboot happens at 05:30, stack self-assembles on boot." \
        https://ntfy.hartforge.dev/homelab-alerts >/dev/null
fi
