#!/usr/bin/env bash

SSH_DROPIN="/etc/ssh/sshd_config.d/99-vps-hardening.conf"

stage_ssh_hardening() {
  if has_checkpoint ssh; then
    log_info "Skipping SSH stage; checkpoint exists"
    return 0
  fi

  log_info "Applying SSH hardening"
  backup_path /etc/ssh/sshd_config
  backup_path /etc/ssh/sshd_config.d

  mkdir -p /etc/ssh/sshd_config.d
  chmod 755 /etc/ssh/sshd_config.d

  ensure_sshd_include
  write_sshd_dropin
  run_cmd sshd -t

  protect_ssh_socket_for_custom_port
  restart_ssh_safely

  checkpoint ssh
}

ensure_sshd_include() {
  if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    return 0
  fi

  log_warn "Adding Include directive to /etc/ssh/sshd_config"
  printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> /etc/ssh/sshd_config
}

write_sshd_dropin() {
  atomic_write_file "$SSH_DROPIN" 644 root root <<EOF
# Managed by vps-init-hardening.
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
ChallengeResponseAuthentication no
X11Forwarding no
AllowUsers $NEW_ADMIN_USER
EOF
}

protect_ssh_socket_for_custom_port() {
  if [[ "$SSH_PORT" == "22" ]]; then
    return 0
  fi

  if systemctl list-unit-files ssh.socket >/dev/null 2>&1; then
    if systemctl is-enabled --quiet ssh.socket || systemctl is-active --quiet ssh.socket; then
      log_warn "Disabling ssh.socket because a custom SSH port is configured"
      add_rollback "re-enable ssh.socket" "systemctl enable --now ssh.socket >/dev/null 2>&1 || true"
      run_cmd systemctl disable --now ssh.socket
      run_cmd systemctl enable ssh.service
    fi
  fi
}

restart_ssh_safely() {
  run_cmd systemctl reload-or-restart ssh.service
  if ! systemctl is-active --quiet ssh.service; then
    die "ssh.service is not active after reload/restart"
  fi
}

