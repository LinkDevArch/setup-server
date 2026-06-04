#!/usr/bin/env bash

stage_fail2ban() {
  if has_checkpoint fail2ban; then
    log_info "Skipping Fail2Ban stage; checkpoint exists"
    return 0
  fi

  log_info "Configuring Fail2Ban"
  backup_path /etc/fail2ban

  atomic_write_file /etc/fail2ban/jail.d/99-vps-sshd.local 644 root root <<EOF
[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
maxretry = 3
findtime = 10m
bantime = 1h
EOF

  if command -v fail2ban-client >/dev/null 2>&1; then
    run_cmd fail2ban-client -t
  fi
  run_cmd systemctl enable fail2ban
  run_cmd systemctl restart fail2ban
  run_cmd systemctl is-active fail2ban

  checkpoint fail2ban
}

