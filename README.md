# VPS Init Hardening for Ubuntu 24.04 LTS (Full Enterprise Suite)

Production-oriented Bash CLI suite to initialize, harden, and audit a fresh **Ubuntu 24.04 LTS** VPS according to **CIS Benchmark (Level 1/2)** and **DevSec Linux Baseline** standards.

The suite configures rootless admin access, enforces modern SSH cryptography, hardens the Linux kernel and network stack, configures UFW firewall with rate limiting, resolves the Docker UFW bypass vulnerability, configures Fail2Ban with native systemd journal integration, automates unattended security updates, establishes CIS audit rules with `auditd`, and optionally integrates **Docker**, **Dokploy**, and **Cloudflare Tunnel (Zero-Trust)** without breaking inter-service connectivity.

---

## Key Features & Security Architecture

- **Ubuntu 24.04 Native Compatibility**: Correctly handles systemd socket activation (`ssh.socket`) vs standalone daemon (`ssh.service`) without false-positive failures or port lockouts.
- **SSH Priority Hardening**: Uses `00-vps-hardening.conf` drop-in to strictly override cloud provider defaults (`50-cloud-init.conf`) under OpenSSH's *first-match-wins* rule. Enforces Curve25519, ChaCha20-Poly1305, and AES-GCM suites.
- **Kernel & Network Sysctl Hardening**: Mitigates SYN floods, IP spoofing (strict reverse path filtering), source routing, and ICMP redirects, while preserving packet forwarding (`ip_forward = 1`) for Docker and Dokploy containers.
- **Docker UFW Protection**: Closes the well-known Docker firewall bypass vulnerability where exposed container ports bypass UFW's `default deny incoming` policy, while preserving internal container bridges and Dokploy Traefik routing.
- **Docker Daemon Hardening**: Configures `/etc/docker/daemon.json` with log rotation (`10m` x 3) to prevent denial-of-service via disk exhaustion, enables `live-restore: true`, and disables `userland-proxy`.
- **Fail2Ban Native Journald**: Includes `python3-systemd` to monitor authentication logs in minimal Ubuntu 24.04 images without requiring `rsyslog`, featuring progressive banning (`bantime.increment = true`).
- **Unattended Security Updates**: Configures daily automatic CVE patching (`unattended-upgrades`) and automated daemon restarts (`needrestart`).
- **NTP Time Synchronization**: Enforces reliable time synchronization via `systemd-timesyncd` for accurate TLS validation and audit trails.
- **CIS Audit Framework (`auditd`)**: Monitors identity files (`/etc/passwd`, `/etc/shadow`), sudoers changes, SSH configuration tampering, and privilege escalation.
- **OS Hardening & Modprobe Blacklisting**: Blacklists obsolete protocols (DCCP, SCTP, RDS, TIPC) and legacy filesystems (cramfs, hfs, jffs2), enforces `umask 027`, disables core dumps, and restricts `su` to the `sudo` group.
- **Bulletproof Step-Based Rollback**: Modular LIFO rollback scripts (`.step`) executed without fragile text manipulations, ensuring all rollback steps execute even if an individual cleanup task warns.

---

## Quick Start

```bash
git clone <this-repo-url> setup-server
cd setup-server
sudo bash start.sh
```

### Non-Interactive Full Hardening Example

```bash
sudo bash start.sh --yes \
  --user deployer \
  --ssh-port 2222 \
  --firewall-mode traditional \
  --install-basic-tools \
  --install-docker \
  --install-dokploy
```

### Ultra-Secure Zero-Trust Setup (Cloudflare Tunnel + Dokploy)

In this mode, all public inbound ports are closed on the firewall (`safe` mode), and services (SSH and Dokploy) are routed through Cloudflare Zero-Trust:

```bash
CLOUDFLARED_TOKEN='your-cloudflare-tunnel-token' sudo -E bash start.sh --yes \
  --user deployer \
  --firewall-mode safe \
  --install-docker \
  --install-dokploy \
  --install-cloudflared
```

### Dry-Run Preview (No Changes Applied)

```bash
sudo bash start.sh --dry-run --config examples/noninteractive.conf
```

---

## Command-Line Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `--config FILE` | Load custom configuration overrides | `config/defaults.conf` |
| `--user NAME` | Dedicated admin user name | `deployer` |
| `--ssh-port PORT` | OpenSSH listening port | `22` |
| `--firewall-mode MODE` | `safe` (SSH only) or `traditional` (SSH + 80 + 443) | `safe` |
| `--install-basic-tools` | Install utilities (curl, wget, htop, tmux, etc.) | `yes` |
| `--no-basic-tools` | Install only minimal required packages | - |
| `--install-docker` | Install official Docker Engine with hardened daemon | `no` |
| `--install-dokploy` | Install Dokploy deployment platform (implies Docker) | `no` |
| `--dokploy-port PORT` | Dokploy onboarding port for UFW in traditional mode | `3000` |
| `--install-cloudflared` | Install and configure Cloudflare Tunnel daemon | `no` |
| `--ssh-public-key-file FILE` | Path to public key file to seed `authorized_keys` | (auto from root) |
| `--no-sysctl` | Disable kernel/network sysctl hardening | - |
| `--no-updates` | Disable automated security updates (`unattended-upgrades`) | - |
| `--no-auditd` | Disable system audit logging framework (`auditd`) | - |
| `--no-system-hardening` | Disable modprobe blacklist and system limits | - |
| `--no-timesync` | Disable NTP time synchronization | - |
| `--no-docker-ufw-fix` | Disable Docker UFW bypass protection rules | - |
| `--no-docker-group` | Do not add admin user to `docker` group | - |
| `--yes`, `-y` | Non-interactive execution with configured defaults | - |
| `--dry-run` | Display execution plan and exit without applying changes | - |
| `--help`, `-h` | Display help screen | - |

---

## Post-Execution Verification Checklist

1. **Verify SSH in a separate window (do not close your root session!)**:
   ```bash
   ssh -p <SSH_PORT> <NEW_ADMIN_USER>@<VPS_IP>
   ```
2. **Verify sudo privileges**:
   ```bash
   sudo -n true
   ```
3. **Verify firewall status & rules**:
   ```bash
   sudo ufw status verbose
   ```
4. **Verify Fail2Ban status & SSH jail**:
   ```bash
   sudo fail2ban-client status sshd
   ```
5. **Verify auditd rules**:
   ```bash
   sudo auditctl -l
   ```
6. **Verify unattended updates**:
   ```bash
   sudo systemctl status unattended-upgrades --no-pager
   ```
7. **If Docker was installed**:
   ```bash
   docker version
   docker info
   ```
8. **If Cloudflare Tunnel was installed**:
   ```bash
   sudo systemctl status cloudflared --no-pager
   ```

---

## Recovery and Rollback

If a failure occurs during execution, the script automatically triggers rollback in reverse order of executed steps.

To trigger manual rollback after a failed run:

```bash
sudo bash rollback.sh
```

Backups are preserved in:
```text
/var/backups/vps-init-hardening/<RUN_ID>/
```

For emergency recovery procedures, see [docs/recovery.md](docs/recovery.md).
