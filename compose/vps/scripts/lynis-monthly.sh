#!/usr/bin/env bash
# monthly lynis scorecard -> ntfy homelab-news
set -euo pipefail
source /opt/scripts/.env

REPORT=$(lynis audit system --quick --no-colors 2>/dev/null)
INDEX=$(echo "$REPORT" | grep -oE "Hardening index : [0-9]+" | grep -oE "[0-9]+" || echo "?")
WARNINGS=$(echo "$REPORT" | grep -cE "warning\[\]" || true)
SUGGESTIONS=$(grep -cE "^suggestion" /var/log/lynis-report.dat 2>/dev/null || echo "?")

curl -fsS -m 10 -u "$NTFY_USER:$NTFY_PASS" \
    -H "Title: lynis monthly: hardening index $INDEX" \
    -d "hardening index: $INDEX/100. suggestions: $SUGGESTIONS. full report: /var/log/lynis.log on the vps." \
    https://ntfy.hartforge.dev/homelab-news >/dev/null
