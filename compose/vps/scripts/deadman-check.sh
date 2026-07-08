#!/bin/bash
# Dead man's switch for Mac Mini
# Runs on VPS, checks Mac Mini via Tailscale
# Alerts via ntfy if both ping and Paimon webhook fail

MAC_MINI_TS="100.112.186.36"
PAIMON_HEALTH="http://${MAC_MINI_TS}:7890/health"
NTFY_URL="https://ntfy.hartforge.dev/homelab-alerts"
STATE_FILE="/tmp/deadman-mac-mini.state"

# Load ntfy credentials
source /opt/scripts/.env 2>/dev/null

# Tailscale self-heal: if tailscaled is wedged, everything below false-alarms
# and SSH to this box is dead. 3 consecutive failures (30 min) -> restart it.
TS_FAIL_FILE="/tmp/deadman-tailscale.fails"
if ! tailscale status > /dev/null 2>&1; then
    TS_FAILS=$(( $(cat "$TS_FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
    echo "$TS_FAILS" > "$TS_FAIL_FILE"
    if [[ $TS_FAILS -eq 3 ]]; then
        systemctl restart tailscaled
        sleep 10
        if tailscale status > /dev/null 2>&1; then TS_RESULT="recovered after restart"; else TS_RESULT="still down after restart - SSH to VPS may be dead, use IONOS VNC console"; fi
        curl -s -u "${NTFY_USER}:${NTFY_PASS}" \
            -H "Title: VPS Tailscale self-heal" \
            -H "Priority: urgent" \
            -d "tailscaled failed 3 consecutive checks, restarted it: ${TS_RESULT}" \
            "$NTFY_URL" > /dev/null 2>&1
        rm -f "$TS_FAIL_FILE"
    fi
    # Tailscale down means the Mac Mini checks below are meaningless - skip them
    exit 0
else
    rm -f "$TS_FAIL_FILE"
fi

# Check ping
ping -c 2 -W 5 "$MAC_MINI_TS" > /dev/null 2>&1
PING_OK=$?

# Check Paimon webhook
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$PAIMON_HEALTH" 2>/dev/null)
if [[ "$HTTP_CODE" =~ ^2 ]]; then
    PAIMON_OK=0
else
    PAIMON_OK=1
fi

if [[ $PING_OK -ne 0 && $PAIMON_OK -ne 0 ]]; then
    # Both checks failed
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "$(date -Iseconds)" > "$STATE_FILE"
        curl -s -u "${NTFY_USER}:${NTFY_PASS}" \
            -H "Title: Mac Mini Down" \
            -H "Priority: urgent" \
            -H "Tags: rotating_light" \
            -d "Mac Mini (100.112.186.36) is unreachable. Ping and Paimon webhook both failed. All cron monitoring, backups, and alerting are offline." \
            "$NTFY_URL" > /dev/null 2>&1
    fi
else
    # At least one check passed -- clear state
    if [[ -f "$STATE_FILE" ]]; then
        curl -s -u "${NTFY_USER}:${NTFY_PASS}" \
            -H "Title: Mac Mini Recovered" \
            -H "Tags: white_check_mark" \
            -d "Mac Mini is back online." \
            "$NTFY_URL" > /dev/null 2>&1
        rm -f "$STATE_FILE"
    fi
fi

# kuma dead-man heartbeat - only reached on success
curl -fsS -m 10 "http://127.0.0.1:3001/api/push/754cb67251b2b9f1" >/dev/null 2>&1 || true
