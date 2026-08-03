# monitoring host env TEMPLATE - safe to commit, contains no secret values.
#   ../render-env.sh monitoring   ->  root@10.1.0.57:/opt/monitoring/.env

# grafana's local admin. kept alongside SSO because losing pocket id must not
# lock us out of the dashboards that would show us why.
GF_SECURITY_ADMIN_PASSWORD={{ op://Homelab/Grafana - local admin login/password }}

# the client ID is not a secret - it is public in every authorize URL.
GRAFANA_OIDC_CLIENT_ID=bccf4195-3720-4c25-ae37-547eb12008ed
GRAFANA_OIDC_CLIENT_SECRET={{ op://Homelab/Grafana - Pocket ID OIDC client secret/credential }}
