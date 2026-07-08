# homelab-compose

docker compose files for hartforge homelab services.

## directories

```
caddy/         - reverse proxy + crowdsec (10.1.0.51)
crucible/      - media stack: jellyfin, *arr, qbit, sabnzbd (10.1.0.52)
forgejo/       - git server mirror (10.1.0.56)
homepage/      - homepage dashboard (10.1.0.54)
immich/        - photo management (10.1.0.59)
monitoring/    - grafana, prometheus, loki (10.1.0.57)
semaphore/     - ansible web UI (10.1.0.81:3100)
uptime-kuma/   - uptime monitoring (10.1.0.53)
```

note: vps services (authentik, ntfy, forgejo primary) live under `/opt/` on the vps and are not tracked here.

## deployment

```bash
# deploy a specific service via ansible
cd ~/Documents/homelab-ansible
ansible-playbook playbooks/deploy-compose.yml --limit <hostname>
```
