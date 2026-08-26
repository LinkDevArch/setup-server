#!/usr/bin/env bash

stage_fail2ban() {
  if has_checkpoint fail2ban; then
    log_info "Skipping Fail2Ban stage; checkpoint exists"
    return 0
  fi

  log_info "Configuring Fail2Ban with systemd journal backend and progressive banning"
  backup_path /etc/fail2ban

  mkdir -p /etc/fail2ban/jail.d

  atomic_write_file /etc/fail2ban/jail.d/00-vps-sshd.local 644 root root <<EOF
# Managed by vps-init-hardening
[DEFAULT]
bantime.increment = true
bantime.rndtime = 15m
bantime.maxtime = 1w
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
mode = aggressive
maxretry = 3
findtime = 10m
bantime = 1h
EOF

  if command -v fail2ban-client >/dev/null 2>&1; then
    run_cmd fail2ban-client -t || die "fail2ban configuration test failed"
  fi

  run_cmd systemctl enable fail2ban
  run_cmd systemctl restart fail2ban
  run_cmd systemctl is-active fail2ban

  checkpoint fail2ban
}
