#!/bin/bash
# nightly restic backup of the vps to the mac mini (rest-server, append-only)
# repo lives at /Users/admin/backups/vps-restic/vps on the mac, reached over
# the wg s2s tunnel. retention/prune runs on the mac side (append-only blocks it here,
# on purpose - a compromised vps can add snapshots but never delete them).
set -o pipefail
source /opt/scripts/restic.env
source /opt/scripts/.env   # NTFY_USER / NTFY_PASS
export RESTIC_REPOSITORY RESTIC_PASSWORD KUMA_PUSH_TOKEN

STAMP() { date '+%F %T'; }
FAIL() {
  echo "$(STAMP) FAILED: $1"
  curl -s -u "${NTFY_USER}:${NTFY_PASS}" \
    -H "Title: VPS backup failed" -H "Priority: 4" -H "Tags: rotating_light" \
    -d "vps-backup.sh: $1" https://ntfy.hartforge.dev/homelab-alerts > /dev/null
  exit 1
}

# consistent copies of the critical live sqlite dbs (restic sees these instead
# of risking torn copies of the hot files)
SQLDIR=/opt/backups/sqlite
mkdir -p "$SQLDIR"
sqlite3 /var/lib/docker/volumes/uptime-kuma_data/_data/kuma.db ".backup '$SQLDIR/kuma.db'" || FAIL "kuma sqlite dump"
sqlite3 /opt/pocket-id/data/pocket-id.db ".backup '$SQLDIR/pocket-id.db'" || FAIL "pocket-id sqlite dump"

# system state worth having next to the data
crontab -l > /opt/backups/crontab.txt 2>/dev/null
ufw status numbered > /opt/backups/ufw-rules.txt 2>/dev/null
dpkg --get-selections > /opt/backups/packages.txt 2>/dev/null

restic backup \
  /opt \
  /etc/caddy \
  /var/lib/docker/volumes/uptime-kuma_data \
  --exclude '/opt/**/.cache' \
  --exclude '/opt/**/cache' \
  --tag nightly \
  --quiet || FAIL "restic backup"

# heartbeat: kuma pages if this stops arriving
curl -fsS -m 10 "http://127.0.0.1:3001/api/push/${KUMA_PUSH_TOKEN}" > /dev/null 2>&1 || true
echo "$(STAMP) backup ok"
