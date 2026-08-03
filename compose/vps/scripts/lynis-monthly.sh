#!/usr/bin/env bash
# monthly lynis scorecard -> ntfy homelab-news
set -euo pipefail
source /opt/scripts/.env

REPORT=$(lynis audit system --quick --no-colors 2>/dev/null)
INDEX=$(echo "$REPORT" | grep -oE "Hardening index : [0-9]+" | grep -oE "[0-9]+" || echo "?")
WARNINGS=$(echo "$REPORT" | grep -cE "warning\[\]" || true)
SUGGESTIONS=$(grep -cE "^suggestion" /var/log/lynis-report.dat 2>/dev/null || echo "?")

/opt/scripts/notify.sh -t news -T "lynis monthly: hardening index $INDEX" \
    -- "hardening index: $INDEX/100. suggestions: $SUGGESTIONS. full report: /var/log/lynis.log on the vps." >/dev/null
