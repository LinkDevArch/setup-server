#!/usr/bin/env bash

stage_timesync() {
  if ! is_yes "$ENABLE_TIMESYNC"; then
    log_info "Skipping timesync stage (disabled by configuration)"
    return 0
  fi

  if has_checkpoint timesync; then
    log_info "Skipping timesync stage; checkpoint exists"
    return 0
  fi

  log_info "Configuring NTP time synchronization via systemd-timesyncd"
  mkdir -p /etc/systemd/timesyncd.conf.d
  backup_path /etc/systemd/timesyncd.conf.d/99-vps-hardening.conf

  atomic_write_file /etc/systemd/timesyncd.conf.d/99-vps-hardening.conf 644 root root <<'EOF'
# Managed by vps-init-hardening
[Time]
NTP=0.ubuntu.pool.ntp.org 1.ubuntu.pool.ntp.org 2.ubuntu.pool.ntp.org 3.ubuntu.pool.ntp.org
FallbackNTP=time.cloudflare.com time.google.com
EOF

  run_cmd systemctl enable systemd-timesyncd
  run_cmd systemctl restart systemd-timesyncd
  if command -v timedatectl >/dev/null 2>&1; then
    run_cmd timedatectl set-ntp true || true
  fi

  checkpoint timesync
}
