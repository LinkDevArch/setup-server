#!/usr/bin/env bash

post_install_checks() {
  log_info "Running post-install checks"

  id "$NEW_ADMIN_USER" >/dev/null 2>&1 || die "Postcheck failed: user missing"
  [[ -s "/home/$NEW_ADMIN_USER/.ssh/authorized_keys" ]] || die "Postcheck failed: authorized_keys missing"
  sshd -t >> "$LOG_FILE" 2>&1 || die "Postcheck failed: sshd -t"
  ufw status | grep -q "Status: active" || die "Postcheck failed: UFW inactive"
  systemctl is-active --quiet ssh.service || die "Postcheck failed: ssh.service inactive"
  systemctl is-active --quiet fail2ban || die "Postcheck failed: fail2ban inactive"

  if is_yes "$INSTALL_DOCKER" || is_yes "$INSTALL_DOKPLOY"; then
    docker version >> "$LOG_FILE" 2>&1 || die "Postcheck failed: Docker not usable"
  fi
  if is_yes "$INSTALL_CLOUDFLARED"; then
    systemctl is-active --quiet cloudflared || die "Postcheck failed: cloudflared inactive"
  fi

  checkpoint postcheck
}

print_summary() {
  cat <<EOF

${green}Completed successfully.${reset}

Access:
  ssh -p $SSH_PORT $NEW_ADMIN_USER@<VPS_IP>

Security state:
  Root SSH login: disabled
  SSH password authentication: disabled
  SSH key authentication: enabled
  UFW mode: $FIREWALL_MODE
  Fail2Ban: enabled for sshd

Files:
  Log: $LOG_FILE
  Backups: $SYSTEM_BACKUP_DIR/$RUN_ID
  State: $STATE_DIR

Important:
  Keep this root session open until you verify a new SSH login in another terminal.
EOF
}

