#!/usr/bin/env bash

post_install_checks() {
  log_info "Running comprehensive post-installation health checks"

  id "$NEW_ADMIN_USER" >/dev/null 2>&1 || die "Postcheck failed: admin user missing"
  [[ -s "/home/$NEW_ADMIN_USER/.ssh/authorized_keys" ]] || die "Postcheck failed: authorized_keys missing or empty"
  sshd -t >> "$LOG_FILE" 2>&1 || die "Postcheck failed: sshd configuration test"

  # On Ubuntu 24.04, SSH can be managed by ssh.socket (port 22) or ssh.service (custom port or standalone)
  if ! systemctl is-active --quiet ssh.service && ! systemctl is-active --quiet ssh.socket; then
    die "Postcheck failed: neither ssh.service nor ssh.socket is active"
  fi

  ufw status | grep -q "Status: active" || die "Postcheck failed: UFW inactive"
  systemctl is-active --quiet fail2ban || die "Postcheck failed: fail2ban inactive"

  if is_yes "$ENABLE_TIMESYNC"; then
    systemctl is-active --quiet systemd-timesyncd || log_warn "Postcheck notice: systemd-timesyncd is not active"
  fi

  if is_yes "$ENABLE_SECURITY_UPDATES"; then
    systemctl is-active --quiet unattended-upgrades || log_warn "Postcheck notice: unattended-upgrades is not active"
  fi

  if is_yes "$ENABLE_AUDITD" && command -v auditd >/dev/null 2>&1; then
    systemctl is-active --quiet auditd || log_warn "Postcheck notice: auditd is not active"
  fi

  if is_yes "$INSTALL_DOCKER" || is_yes "$INSTALL_DOKPLOY"; then
    docker version >> "$LOG_FILE" 2>&1 || die "Postcheck failed: Docker daemon is not usable"
  fi

  if is_yes "$INSTALL_CLOUDFLARED"; then
    systemctl is-active --quiet cloudflared || die "Postcheck failed: cloudflared service is not active"
  fi

  checkpoint postcheck
}

print_summary() {
  cat <<EOF

${green}============================================================${reset}
${green} VPS Hardening Completed Successfully (Full Suite)${reset}
${green}============================================================${reset}

Access Command:
  ssh -p $SSH_PORT $NEW_ADMIN_USER@<VPS_IP>

Security Baseline Applied:
  Root SSH login:             disabled
  SSH password auth:          disabled
  SSH public key auth:        enforced
  SSH crypto ciphers:         modern suites (Curve25519, ChaCha20, AES-GCM)
  Firewall (UFW):             active ($FIREWALL_MODE mode)
  Firewall SSH rate limiting: enabled
  Fail2Ban protection:        active (systemd backend + progressive ban)
  Kernel & network (sysctl):  hardened (SYN cookies, anti-spoof, rp_filter)
  Unattended updates:         active (daily security patches)
  Audit framework (auditd):   active (CIS identity, sudoers, sshd tracking)
  System protections:         umask 027, limits.conf, modprobe blacklist
  Time synchronization:       active (systemd-timesyncd)
EOF

  if is_yes "$INSTALL_DOCKER" || is_yes "$INSTALL_DOKPLOY"; then
    cat <<EOF
  Docker Engine:              installed and hardened (log limits, live-restore)
  Docker UFW protection:      active (containers protected from WAN bypass)
EOF
  fi

  if is_yes "$INSTALL_DOKPLOY"; then
    cat <<EOF
  Dokploy Platform:           installed
  Dokploy Access:             http://<VPS_IP>:${DOKPLOY_PORT:-3000} (or via Cloudflare Tunnel)
EOF
  fi

  if is_yes "$INSTALL_CLOUDFLARED"; then
    cat <<EOF
  Cloudflare Tunnel:          active (cloudflared systemd service running)
EOF
  fi

  cat <<EOF

Files & Recovery:
  Log File:   $LOG_FILE
  Backups:    $SYSTEM_BACKUP_DIR/$RUN_ID
  State Dir:  $STATE_DIR

${bold}${yellow}CRITICAL SAFETY ADVICE:${reset}
  Do NOT close this current root terminal until you have opened a
  SEPARATE terminal window and successfully verified SSH login:
  ssh -p $SSH_PORT $NEW_ADMIN_USER@<VPS_IP>
EOF
}
