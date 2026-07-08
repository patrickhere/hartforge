#!/usr/bin/env bash
# monthly: diun can't see the custom caddy binary, so check upstream releases here.
# reports when caddy or the crowdsec bouncer plugin has a newer release than installed.
set -euo pipefail
source /opt/scripts/.env

INSTALLED=$(caddy version | awk '{print $1}')   # e.g. v2.11.4
LATEST_CADDY=$(curl -fsS -m 30 https://api.github.com/repos/caddyserver/caddy/releases/latest | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4)
LATEST_BOUNCER=$(curl -fsS -m 30 https://api.github.com/repos/hslatman/caddy-crowdsec-bouncer/releases/latest | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4)

MSG=""
if [ -n "$LATEST_CADDY" ] && [ "$LATEST_CADDY" != "$INSTALLED" ]; then
    MSG="caddy: $INSTALLED -> $LATEST_CADDY available."
fi
if [ -n "$LATEST_BOUNCER" ]; then
    MSG="$MSG bouncer latest: $LATEST_BOUNCER (rebuild recipe in homelab-docs / vps-caddy memory)."
fi

if [ -n "$MSG" ] && [ "$LATEST_CADDY" != "$INSTALLED" ]; then
    curl -fsS -m 10 -u "$NTFY_USER:$NTFY_PASS" \
        -H "Title: custom caddy build update available" \
        -d "$MSG rebuild: xcaddy build $LATEST_CADDY --with github.com/hslatman/caddy-crowdsec-bouncer" \
        https://ntfy.hartforge.dev/homelab-news >/dev/null
fi
