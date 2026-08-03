# secrets for the /opt/yams/scripts/* jobs on 10.1.0.52.
#   ../../render-env.sh crucible/scripts   ->  root@10.1.0.52:/opt/yams/scripts/.env
#
# TMDB has TWO credentials and they are not interchangeable. the v3 API key is
# the 32-hex string this file wants; the vault item "TMDB - API key" holds the
# v4 read access token (a 244-char JWT out of posterizarr's config). referencing
# the wrong one renders a value that looks fine and fails at the API.

JF_KEY={{ op://Homelab/Jellyfin - API key/credential }}
JF_SOURCE_ID=27cd0f32-1e5f-465e-8a4a-0846ee6f2668
STUDIO_JF_KEY={{ op://Homelab/Jellyfin - API key - studio user/credential }}
TMDB_KEY={{ op://Homelab/TMDB - v3 API key/credential }}
