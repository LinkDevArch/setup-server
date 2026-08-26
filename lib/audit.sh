#!/usr/bin/env bash

stage_audit() {
  if ! is_yes "$ENABLE_AUDITD"; then
    log_info "Skipping auditd stage (disabled by configuration)"
    return 0
  fi

  if has_checkpoint audit; then
    log_info "Skipping audit stage; checkpoint exists"
    return 0
  fi

  if ! command -v auditd >/dev/null 2>&1; then
    log_warn "auditd is not installed; skipping audit stage"
    return 0
  fi

  log_info "Configuring auditd logging rules (CIS Benchmark standard)"
  mkdir -p /etc/audit/rules.d
  backup_path /etc/audit/rules.d/99-vps-hardening.rules

  local arch_rules=""
  if [[ "$DEB_ARCH" == "amd64" ]]; then
    arch_rules="-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k setuid
-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k setuid"
  elif [[ "$DEB_ARCH" == "arm64" ]]; then
    arch_rules="-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k setuid"
  fi

  atomic_write_file /etc/audit/rules.d/99-vps-hardening.rules 640 root root <<EOF
# Managed by vps-init-hardening
# Delete all existing rules first
-D
-b 8192

# Monitor Identity and Authentication Files
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor Sudoers Changes
-w /etc/sudoers -p wa -k sudo_changes
-w /etc/sudoers.d/ -p wa -k sudo_changes

# Monitor SSH Configuration
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config

# Monitor System Time Changes
-w /etc/localtime -p wa -k time-change

# Architecture Specific System Call Auditing
$arch_rules

# Make configuration immutable until reboot (optional/standard in CIS)
-e 1
EOF

  if command -v augenrules >/dev/null 2>&1; then
    run_cmd augenrules --load || true
  fi

  run_cmd systemctl enable auditd || true
  run_cmd systemctl restart auditd || true

  checkpoint audit
}
