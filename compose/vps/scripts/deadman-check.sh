#!/bin/bash
# Dead man's switch for Mac Mini
# Runs on VPS, checks Mac Mini via the wg s2s tunnel
# Alerts via ntfy if both ping and Paimon webhook fail

MAC_MINI_TS="10.1.0.81"
PAIMON_HEALTH="http://${MAC_MINI_TS}:7890/health"
NTFY_URL="https://ntfy.hartforge.dev/homelab-alerts"
STATE_FILE="/tmp/deadman-mac-mini.state"

# Load ntfy credentials
source /opt/scripts/.env 2>/dev/null

# wg-s2s self-heal: if the tunnel is wedged, everything below false-alarms.
# 3 consecutive stale handshakes (30 min) -> restart wg-quick@wg-s2s.
WG_FAIL_FILE="/tmp/deadman-wgs2s.fails"
HS=$(wg show wg-s2s latest-handshakes 2>/dev/null | awk "{print \$2}")
NOW=$(date +%s)
if [[ -z "$HS" || $(( NOW - HS )) -gt 300 ]]; then
    WG_FAILS=$(( $(cat "$WG_FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
    echo "$WG_FAILS" > "$WG_FAIL_FILE"
    if [[ $WG_FAILS -eq 3 ]]; then
        systemctl restart wg-quick@wg-s2s
        sleep 30
        HS2=$(wg show wg-s2s latest-handshakes 2>/dev/null | awk "{print \$2}")
        if [[ -n "$HS2" && $(( $(date +%s) - HS2 )) -lt 60 ]]; then WG_RESULT="recovered after restart"; else WG_RESULT="still down after restart - home side or ionos issue"; fi
        curl -s -u "${NTFY_USER}:${NTFY_PASS}" \
            -H "Title: VPS wg-s2s self-heal" \
            -H "Priority: urgent" \
            -d "wg-s2s handshake stale 3 consecutive checks, restarted it: ${WG_RESULT}" \
            "$NTFY_URL" > /dev/null 2>&1
        rm -f "$WG_FAIL_FILE"
    fi
    # tunnel down means the Mac Mini checks below are meaningless - skip them
    exit 0
else
    rm -f "$WG_FAIL_FILE"
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
            -d "Mac Mini (10.1.0.81 via wg-s2s) is unreachable. Ping and Paimon webhook both failed. All cron monitoring, backups, and alerting are offline." \
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
