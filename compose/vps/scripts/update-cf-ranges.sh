#!/usr/bin/env bash
# syncs cloudflare's published ranges to BOTH consumers from one fetch:
#   - /etc/caddy/cf_trusted_proxies.caddy (trusted_proxies, v4+v6, caddy reload on change)
#   - ufw 80/443 allow rules tagged "# Cloudflare edge" (v4 only - box has no public v6)
# weekly cron. ntfy on change or failure.
set -euo pipefail

SNIPPET="/etc/caddy/cf_trusted_proxies.caddy"
NTFY_URL="https://ntfy.hartforge.dev/homelab-alerts"
UFW_TAG="# Cloudflare edge"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# ntfy is deny-all - publishing needs the pub-vps credentials
. /opt/scripts/.env

notify() {
    # priority, title, message
    curl -fsS -m 10 -u "$NTFY_USER:$NTFY_PASS" -H "Priority: $1" -H "Title: $2" -H "Tags: cloud" \
        -d "$3" "$NTFY_URL" >/dev/null 2>&1 || true
}

fail() {
    notify high "CF ranges update failed" "$1"
    echo "ERROR: $1" >&2
    exit 1
}

V4=$(curl -fsS -m 30 https://www.cloudflare.com/ips-v4) || fail "could not fetch ips-v4"
V6=$(curl -fsS -m 30 https://www.cloudflare.com/ips-v6) || fail "could not fetch ips-v6"

# sanity: both lists non-empty, look like CIDRs, and v4 isn't suspiciously short
echo "$V4" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' || fail "ips-v4 response looks wrong"
echo "$V6" | grep -qiE '^[0-9a-f:]+/[0-9]+$' || fail "ips-v6 response looks wrong"
[ "$(echo "$V4" | wc -l)" -ge 5 ] || fail "ips-v4 returned fewer than 5 ranges, refusing to act"

CHANGES=""

# ---- caddy trusted_proxies (v4 + v6) ----

RANGES=$(printf '%s\n%s\n' "$V4" "$V6" | tr '\n' ' ' | sed 's/ *$//')
printf 'trusted_proxies static %s\n' "$RANGES" > "$TMP"

if ! { [ -f "$SNIPPET" ] && cmp -s "$TMP" "$SNIPPET"; }; then
    [ -f "$SNIPPET" ] && cp "$SNIPPET" "$SNIPPET.prev"
    cp "$TMP" "$SNIPPET"
    chmod 644 "$SNIPPET"

    # caddy validate needs the same env the service gets (crowdsec api key etc)
    set -a; . /etc/caddy/caddy.env; set +a

    if ! caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        [ -f "$SNIPPET.prev" ] && cp "$SNIPPET.prev" "$SNIPPET"
        fail "caddy validate failed with new CF ranges - rolled snippet back, caddy not reloaded"
    fi

    systemctl reload caddy || fail "caddy reload failed after CF range update"
    CHANGES="caddy trusted_proxies updated"
fi

# ---- ufw 80/443 rules (v4) ----
# idempotent sync: add missing ranges first, then drop stale ones by rule number
# (add-before-delete so cloudflare is never fully blocked mid-sync)

CURRENT=$(ufw status | awk -v tag="$UFW_TAG" 'index($0, tag) && $1=="80,443/tcp" {print $4}')

ADDED=0
while IFS= read -r cidr; do
    echo "$CURRENT" | grep -qxF "$cidr" && continue
    ufw allow proto tcp from "$cidr" to any port 80,443 comment "Cloudflare edge" >/dev/null \
        || fail "ufw add failed for $cidr"
    ADDED=$((ADDED+1))
done <<< "$V4"

REMOVED=0
# collect stale rule numbers, delete highest-first so numbering stays valid
# "[ 3]" pads single digits with a space, so normalize with sed rather than awk fields
STALE=$(ufw status numbered | grep -F "$UFW_TAG" | grep -F "80,443/tcp" \
    | sed -E 's/^\[\s*([0-9]+)\]\s+[^ ]+\s+ALLOW IN\s+([^ ]+).*/\1 \2/' | sort -rn)
while read -r num cidr; do
    [ -n "$num" ] || continue
    echo "$V4" | grep -qxF "$cidr" && continue
    ufw --force delete "$num" >/dev/null || fail "ufw delete failed for rule $num ($cidr)"
    REMOVED=$((REMOVED+1))
done <<< "$STALE"

# never leave cloudflare fully blocked
FINAL=$(ufw status | grep -cF "$UFW_TAG") || true
[ "$FINAL" -ge 5 ] || fail "ufw ended with only $FINAL cloudflare rules - manual check needed NOW"

if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
    CHANGES="${CHANGES:+$CHANGES; }ufw +$ADDED/-$REMOVED rules"
fi

[ -n "$CHANGES" ] && notify default "CF ranges updated" "$CHANGES"

# kuma dead-man heartbeat - only reached on success
curl -fsS -m 10 "http://127.0.0.1:3001/api/push/9477cc306765443c" >/dev/null 2>&1 || true
exit 0
