# VPS Init Hardening for Ubuntu 24.04 LTS

Production-oriented Bash CLI to initialize and harden a fresh Ubuntu 24.04 LTS VPS. It creates an administrator user, copies SSH keys, hardens SSH, configures UFW and Fail2Ban, and can optionally install Docker, Dokploy, and Cloudflare Tunnel.

## Quick Start

```bash
git clone <this-repo-url> setup-server
cd setup-server
sudo bash start.sh
```

Non-interactive example:

```bash
sudo bash start.sh --yes \
  --user deployer \
  --ssh-port 2222 \
  --firewall-mode traditional \
  --install-basic-tools \
  --install-docker
```

Preview only:

```bash
sudo bash start.sh --dry-run --config examples/noninteractive.conf
```

## Requirements

- Ubuntu 24.04 LTS.
- Run as root, normally with `sudo bash start.sh`.
- Existing root SSH public key in `/root/.ssh/authorized_keys`, or pass `--ssh-public-key-file /path/to/key.pub`.
- Network access to Ubuntu repositories. Optional components require Docker, Cloudflare, or Dokploy endpoints.

## Options

```text
--config FILE
--user NAME
--ssh-port PORT
--firewall-mode safe|traditional
--install-basic-tools
--no-basic-tools
--install-docker
--install-dokploy
--install-cloudflared
--ssh-public-key-file FILE
--yes
--dry-run
```

For Cloudflare Tunnel:

```bash
CLOUDFLARED_TOKEN='token-from-cloudflare' sudo -E bash start.sh --yes --install-cloudflared
```

The token is not written to config files by this project and is redacted from command logging.

## What It Changes

- Creates an admin user with passwordless sudo.
- Copies validated SSH public keys to the new user.
- Writes `/etc/ssh/sshd_config.d/99-vps-hardening.conf`.
- Disables SSH root login and SSH password authentication.
- Allows only the created admin user via SSH.
- Configures UFW:
  - `safe`: SSH port only.
  - `traditional`: SSH port plus 80 and 443.
- Configures Fail2Ban for `sshd` using the `systemd` backend.
- Optionally installs Docker Engine from Docker's official apt repository.
- Optionally installs Dokploy only when explicitly selected.
- Optionally installs `cloudflared` from Cloudflare's apt repository.

## Safety Model

- Bash strict mode: `set -Eeuo pipefail`.
- Single-process lock in `/var/lib/vps-init-hardening/lock`.
- Checkpoints in `/var/lib/vps-init-hardening/checkpoints`.
- Backups before modifying important paths in `/var/backups/vps-init-hardening/<RUN_ID>`.
- Rollback actions are registered as stages complete.
- SSH is validated with `sshd -t` before reload/restart.
- Sudoers is validated with `visudo -cf`.
- Fail2Ban is validated with `fail2ban-client -t`.
- SSH changes are applied through a drop-in file, not destructive edits.

Keep the original root session open until this succeeds from a second terminal:

```bash
ssh -p <SSH_PORT> <NEW_ADMIN_USER>@<VPS_IP>
```

## Rollback

Automatic rollback runs on failures for registered reversible actions.

Manual rollback after a failed run:

```bash
sudo bash rollback.sh
```

Rollback scripts are kept in:

```text
/var/lib/vps-init-hardening/rollback-<RUN_ID>.sh
```

Backups are kept in:

```text
/var/backups/vps-init-hardening/<RUN_ID>
```

For emergency access recovery, see [docs/recovery.md](docs/recovery.md).

## Re-run and Resume

The script is idempotent and stores checkpoints. Re-running after a failed execution skips completed stages and continues pending work. Re-running after a successful execution reconciles the current configuration again, so changed parameters such as `--ssh-port` are applied intentionally.

To intentionally re-apply from scratch, inspect the current state first, then remove checkpoints:

```bash
sudo rm -rf /var/lib/vps-init-hardening/checkpoints
sudo bash start.sh --yes
```

Do not remove backups until you have verified stable access.

## Post-Execution Checklist

- `ssh -p <port> <user>@<ip>` works in a new terminal.
- `sudo -n true` works as the new user.
- `sudo sshd -t` returns success.
- `sudo ufw status verbose` shows the intended SSH rule and only intended web ports.
- `sudo systemctl status fail2ban --no-pager` is active.
- If Docker was selected, `docker version` succeeds.
- If Cloudflare Tunnel was selected, `systemctl status cloudflared --no-pager` is active.
- Root SSH login no longer works.
- SSH password login no longer works.

## Technical Decisions and Assumptions

- Ubuntu 24.04 LTS only, because SSH socket behavior and package repositories vary by release.
- SSH hardening is written as a dedicated drop-in for auditability and rollback.
- The firewall is not reset, to avoid deleting provider or user rules unexpectedly.
- Docker uses the official apt repository instead of the convenience script.
- Cloudflare Tunnel uses Cloudflare's apt repository and architecture-aware apt metadata.
- Dokploy is optional and explicit. Its upstream installer is downloaded to disk before execution so it is auditable and avoids direct `curl | sh`.
