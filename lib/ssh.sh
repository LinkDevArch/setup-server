#!/usr/bin/env bash

# Naming drop-in 00- ensures priority over 50-cloud-init.conf in OpenSSH's first-match-wins model
SSH_DROPIN="/etc/ssh/sshd_config.d/00-vps-hardening.conf"
OLD_SSH_DROPIN="/etc/ssh/sshd_config.d/99-vps-hardening.conf"

stage_ssh_hardening() {
  if has_checkpoint ssh && [[ -f "$SSH_DROPIN" ]] && (systemctl is-active --quiet ssh.service || systemctl is-active --quiet ssh.socket); then
    log_info "Skipping SSH stage; checkpoint, configuration, and service exist"
    return 0
  fi

  log_info "Applying OpenSSH hardening for Ubuntu 24.04 LTS"
  backup_path /etc/ssh/sshd_config
  backup_path /etc/ssh/sshd_config.d

  mkdir -p /etc/ssh/sshd_config.d
  chmod 755 /etc/ssh/sshd_config.d

  # Clean up legacy 99- file if present from prior versions
  if [[ -f "$OLD_SSH_DROPIN" ]]; then
    rm -f "$OLD_SSH_DROPIN"
  fi

  ensure_sshd_include
  write_sshd_dropin

  # Strictly test SSH configuration syntax before touching running services
  run_cmd sshd -t || die "sshd -t validation failed for $SSH_DROPIN"

  handle_ssh_service_and_socket
  checkpoint ssh
}

ensure_sshd_include() {
  if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    return 0
  fi

  log_warn "Adding Include directive to the top of /etc/ssh/sshd_config"
  local tmp
  tmp="$(mktemp)"
  printf 'Include /etc/ssh/sshd_config.d/*.conf\n\n' > "$tmp"
  cat /etc/ssh/sshd_config >> "$tmp"
  cat "$tmp" > /etc/ssh/sshd_config
  rm -f "$tmp"
}

write_sshd_dropin() {
  atomic_write_file "$SSH_DROPIN" 644 root root <<EOF
# OpenSSH Hardening Configuration
# Managed by vps-init-hardening (evaluated first due to 00- prefix)

Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers $NEW_ADMIN_USER

# Network & Session Protection
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
MaxSessions 4
MaxStartups 10:30:100
LogLevel VERBOSE
PermitEmptyPasswords no
IgnoreRhosts yes
HostbasedAuthentication no
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding no
UseDNS no
GSSAPIAuthentication no

# Modern Cryptographic Suites (CIS Benchmark / RFC 4253 recommendations)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
EOF
}

handle_ssh_service_and_socket() {
  run_cmd systemctl daemon-reload

  if [[ "$SSH_PORT" == "22" ]]; then
    # On Ubuntu 24.04, default port 22 is managed by ssh.socket by default
    if systemctl list-unit-files ssh.socket >/dev/null 2>&1 && (systemctl is-active --quiet ssh.socket || systemctl is-enabled --quiet ssh.socket); then
      log_info "Managing SSH on port 22 via ssh.socket"
      run_cmd systemctl restart ssh.socket
      run_cmd systemctl reload-or-restart ssh.service || true
      if ! systemctl is-active --quiet ssh.socket && ! systemctl is-active --quiet ssh.service; then
        die "Neither ssh.socket nor ssh.service is active on port 22"
      fi
    else
      log_info "Managing SSH on port 22 via ssh.service"
      run_cmd systemctl enable --now ssh.service
      run_cmd systemctl restart ssh.service
      if ! systemctl is-active --quiet ssh.service; then
        die "ssh.service is not active after restart"
      fi
    fi
  else
    # Custom port requires stopping, disabling and masking ssh.socket on Ubuntu 24.04 to prevent port 22 binding conflict
    log_info "Custom SSH port ($SSH_PORT) detected: stopping and masking ssh.socket, enabling standalone ssh.service"
    if systemctl list-unit-files ssh.socket >/dev/null 2>&1; then
      add_rollback "re-enable ssh.socket" "systemctl unmask ssh.socket >/dev/null 2>&1 || true; systemctl enable --now ssh.socket >/dev/null 2>&1 || true"
      run_cmd systemctl stop ssh.socket || true
      run_cmd systemctl disable --now ssh.socket || true
      run_cmd systemctl mask ssh.socket || true
    fi

    # Clean up any orphaned sshd daemon processes lingering on port 22
    if command -v fuser >/dev/null 2>&1; then
      fuser -k 22/tcp >/dev/null 2>&1 || true
    fi
    local old_pids
    old_pids="$(ss -tulpn 2>/dev/null | awk '/:22 / {print $7}' | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u)"
    for pid in $old_pids; do
      if [[ -n "$pid" && "$pid" != "$$" ]]; then
        log_info "Terminating legacy sshd process on port 22 (PID $pid)"
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    done

    run_cmd systemctl daemon-reload
    run_cmd systemctl enable --now ssh.service
    run_cmd systemctl restart ssh.service
    sleep 1

    if ! systemctl is-active --quiet ssh.service; then
      die "ssh.service is not active on custom port $SSH_PORT"
    fi
  fi
}
