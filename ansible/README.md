# homelab-ansible

ansible playbooks, roles, and inventory for the hartforge homelab.

## quick start

```bash
# install required collections
ansible-galaxy install -r requirements.yml

# health check all hosts
ansible-playbook playbooks/health-check.yml

# bootstrap a new LXC
ansible-playbook playbooks/bootstrap-lxc.yml --limit <hostname> -e install_docker=true
```

## playbooks

### operations
```
health-check.yml     - full health check (uptime, memory, disk, docker, service verify)
status.yml           - quick status for all linux hosts
docker-status.yml    - show docker containers on all hosts
vps-status.yml       - vps-specific checks (swap, firewall, caddy, containers)
update-all.yml       - rolling apt dist-upgrade with health checks between each host
disk-cleanup.yml     - clean apt cache, docker prune, log rotation
self-heal.yml        - auto-restart crashed containers, prune if disk high
```

### deployment
```
bootstrap-lxc.yml    - bootstrap a new LXC with roles (common, docker, alloy, motd)
provision-lxc.yml    - create LXCs on proxmox from definitions (-e target=<hostname>)
deploy-compose.yml   - deploy docker compose stacks from homelab-compose repo
deploy-ssh-key.yml   - deploy ssh keys from group_vars to all hosts
deploy-motd.yml      - deploy hart forge MOTD to all linux hosts
register-monitoring.yml - add host to prometheus scrape targets
```

### security
```
ssh-hardening.yml    - harden sshd_config across all hosts
firewall-audit.yml   - read-only audit of iptables rules and listening ports
docker-audit.yml     - audit docker security (root containers, privileged, exposed ports)
```

### backup and recovery
```
backup-configs.yml   - backup all homelab configs (caddy, yams, forgejo, monitoring, immich, vps)
config-drift.yml     - detect drift between live configs and homelab-compose repo
snapshot-create.yml  - create proxmox snapshots before maintenance
disaster-recovery.yml - rebuild entire homelab from scratch
```

## roles

```
common          - timezone, base packages, ssh keys
docker          - docker CE install + daemon.json config
alloy           - grafana alloy log shipper
node_exporter   - prometheus node-exporter
motd            - hart forge MOTD deployment
```

## inventory

```
inventory/
  hosts.yml          - host IPs and group membership
  group_vars/
    all.yml          - shared defaults (timezone, ssh keys, packages)
    all/vault.yml    - encrypted secrets (future)
  host_vars/
    <hostname>.yml   - per-host vars (svc_name, svc_check, backup_files, compose_path)
```

### groups

`proxmox`, `media`, `infra`, `apps`, `monitoring`, `network`, `vps`, `macos`, `linux`, `docker`

## tags

most playbooks support tags for selective execution:

```bash
# just run docker tasks on a bootstrap
ansible-playbook playbooks/bootstrap-lxc.yml --limit <host> --tags docker

# just verify services in health check
ansible-playbook playbooks/health-check.yml --tags health
```
