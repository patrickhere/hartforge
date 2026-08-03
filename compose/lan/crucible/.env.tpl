# crucible host env TEMPLATE - safe to commit, contains no secret values.
#   ../render-env.sh crucible   ->  root@10.1.0.52:/opt/crucible/.env
#
# the five *arr keys were verified byte-identical to their vault items on
# 08-01-2026 before this template was written. do not assume that for new ones -
# render-env.sh diffs key by key against the live file and will say so.

PUID=1001
PGID=1001
TZ=America/Chicago
MEDIA_DIRECTORY=/mnt/mediapool
INSTALL_DIRECTORY=/opt/yams

# Jellyfin stats
JELLYSTAT_POSTGRES_PASSWORD={{ op://Homelab/Jellystat - postgres password/credential }}
JELLYSTAT_JWT_SECRET={{ op://Homelab/Jellystat - JWT secret/credential }}

# Arr API keys (used by exportarr + unpackerr)
SONARR_API_KEY={{ op://Homelab/Sonarr - API key/credential }}
RADARR_API_KEY={{ op://Homelab/Radarr - API key/credential }}
LIDARR_API_KEY={{ op://Homelab/Lidarr - API key/credential }}
SABNZBD_API_KEY={{ op://Homelab/SABnzbd - API key/credential }}
PROWLARR_API_KEY={{ op://Homelab/Prowlarr - API key/credential }}

# merged from /opt/yams/.env during 07-13-2026 consolidation.
# VPN_USER/VPN_PASSWORD are the upstream PLACEHOLDER strings, not credentials -
# VPN_ENABLED=n, nothing reads them. they stay literal on purpose; putting
# placeholders in the vault would imply there is a secret to protect.
MEDIA_SERVICE=jellyfin
VPN_ENABLED=n
VPN_SERVICE=vpn_service
VPN_USER=vpn_user
VPN_PASSWORD=vpn_password
