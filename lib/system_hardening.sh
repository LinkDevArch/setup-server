#!/usr/bin/env bash

stage_system_hardening() {
  if ! is_yes "$ENABLE_SYSTEM_HARDENING"; then
    log_info "Skipping system hardening stage (disabled by configuration)"
    return 0
  fi

  if has_checkpoint system-hardening; then
    log_info "Skipping system hardening stage; checkpoint exists"
    return 0
  fi

  log_info "Applying system-level OS hardening (modprobe, umask, limits, pam)"

  # 1. Modprobe blacklisting for obsolete protocols and legacy filesystems
  mkdir -p /etc/modprobe.d
  backup_path /etc/modprobe.d/99-vps-hardening-blacklist.conf

  atomic_write_file /etc/modprobe.d/99-vps-hardening-blacklist.conf 644 root root <<'EOF'
# Obsolete and vulnerable network protocols
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true

# Legacy filesystems (squashfs is intentionally kept for snapd)
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
EOF

  # 2. Disable core dumps via PAM limits
  mkdir -p /etc/security/limits.d
  backup_path /etc/security/limits.d/10-disable-coredumps.conf

  atomic_write_file /etc/security/limits.d/10-disable-coredumps.conf 644 root root <<'EOF'
# Managed by vps-init-hardening
* hard core 0
* soft core 0
EOF

  # 3. Restrict default umask to 027
  backup_path /etc/profile.d/99-vps-hardening-umask.sh
  atomic_write_file /etc/profile.d/99-vps-hardening-umask.sh 644 root root <<'EOF'
# Managed by vps-init-hardening
umask 027
EOF

  if [[ -f /etc/login.defs ]]; then
    backup_path /etc/login.defs
    sed -i 's/^[[:space:]]*UMASK[[:space:]]\+[0-9]\+/UMASK 027/' /etc/login.defs || true
  fi

  # 4. Mask ctrl-alt-del reboot target
  run_cmd systemctl mask ctrl-alt-del.target || true

  # 5. Restrict 'su' command to users in sudo group
  if [[ -f /etc/pam.d/su ]]; then
    backup_path /etc/pam.d/su
    if ! grep -q "pam_wheel.so" /etc/pam.d/su; then
      printf '\n# Restrict su to sudo group\nauth required pam_wheel.so use_uid group=sudo\n' >> /etc/pam.d/su
    fi
  fi

  # 6. Set inactive account lock to 30 days
  run_cmd useradd -D -f 30 || true

  checkpoint system-hardening
}
