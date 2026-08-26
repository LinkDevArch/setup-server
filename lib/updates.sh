#!/usr/bin/env bash

stage_updates() {
  if ! is_yes "$ENABLE_SECURITY_UPDATES"; then
    log_info "Skipping unattended security updates stage (disabled by configuration)"
    return 0
  fi

  if has_checkpoint updates; then
    log_info "Skipping unattended updates stage; checkpoint exists"
    return 0
  fi

  log_info "Configuring unattended security upgrades and needrestart"
  backup_path /etc/apt/apt.conf.d/20auto-upgrades
  backup_path /etc/apt/apt.conf.d/50unattended-upgrades

  atomic_write_file /etc/apt/apt.conf.d/20auto-upgrades 644 root root <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

  atomic_write_file /etc/apt/apt.conf.d/50unattended-upgrades 644 root root <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

  # Configure needrestart for automatic non-interactive daemon restarts
  if [[ -d /etc/needrestart ]]; then
    mkdir -p /etc/needrestart/conf.d
    backup_path /etc/needrestart/conf.d/99-vps-hardening.conf
    atomic_write_file /etc/needrestart/conf.d/99-vps-hardening.conf 644 root root <<'EOF'
# Managed by vps-init-hardening
# Automatically restart services when shared libraries are updated
$nrconf{restart} = 'a';
EOF
  fi

  run_cmd systemctl enable unattended-upgrades
  run_cmd systemctl restart unattended-upgrades

  checkpoint updates
}
