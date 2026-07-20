# hartforge

infrastructure code for the hart forge homelab - a self-hosted platform running on
proxmox at home plus one small VPS, managed end to end as code.

this is a curated public snapshot of the private working repos. secrets are vaulted
or env-injected, and a few addresses are swapped for documentation ranges. everything
else is the real config that runs the lab.

## what runs here

- **proxmox VE** hosting a mix of VMs and LXC containers (media stack, photos,
  DNS, monitoring, reverse proxy)
- **IONOS VPS** as the public edge - identity, git, notifications, and anything
  that should survive the house losing power
- **wireguard** stitching the two together - a plain wg site-to-site tunnel,
  managed with WGDashboard, home side dials out

## layout

```
ansible/       playbooks, roles, and inventory for the whole fleet
compose/lan/   docker compose for services on the home network
compose/vps/   docker compose + scripts for the public VPS
motd/          catppuccin MOTD system with a pokemon buddy per host
```

## highlights

- `ansible/playbooks/` - 20 playbooks covering health checks, updates, config
  drift detection, disaster recovery, LXC provisioning, and self-healing
- `compose/vps/caddy-Caddyfile` - caddy with the crowdsec bouncer plugin, every
  vhost behind a shared hardening snippet, auth via pocket ID (passkey OIDC)
  and tinyauth forward auth
- `compose/vps/scripts/` - the operational glue: cloudflare IP range sync into
  caddy + UFW, a deadman switch, release watchers, scheduled audits
- `motd/` - every host greets you with its own pokemon, named per machine
- monitoring is push-based where it matters: uptime kuma heartbeats wired into
  the cron jobs themselves, so a dead script pages instead of silently stopping
- agentic coding is part of the toolchain: a persistent claude-based agent with
  SSH access to the fleet handles ops, audits, and deployments alongside me -
  much of what's in this repo was built and is maintained that way

## notes

- `ansible/vars/secrets.yml` is ansible-vault encrypted in the working repo and
  excluded here; playbooks reference it for tokens (ntfy, forgejo, proxmox API)
- compose files expect `.env` files documented by the `.env.example` next to them
- this snapshot is refreshed manually from the working repos, so it may trail
  reality by a bit
