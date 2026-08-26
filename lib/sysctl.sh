#!/usr/bin/env bash

SYSCTL_CONF="/etc/sysctl.d/99-vps-hardening.conf"

stage_sysctl() {
  if ! is_yes "$ENABLE_SYSCTL_HARDENING"; then
    log_info "Skipping sysctl hardening stage (disabled by configuration)"
    return 0
  fi

  if has_checkpoint sysctl; then
    log_info "Skipping sysctl hardening stage; checkpoint exists"
    return 0
  fi

  log_info "Applying Linux kernel and network stack hardening (sysctl)"
  backup_path "$SYSCTL_CONF"

  local forward_setting="0"
  if is_yes "$INSTALL_DOCKER" || is_yes "$INSTALL_DOKPLOY" || command -v docker >/dev/null 2>&1; then
    log_info "Preserving packet forwarding for Docker and Dokploy compatibility"
    forward_setting="1"
  fi

  atomic_write_file "$SYSCTL_CONF" 644 root root <<EOF
# Linux Kernel and Network Hardening
# Managed by vps-init-hardening

# Network Security - SYN Flood, Time-wait, and ICMP
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Packet Forwarding (Docker/Dokploy requires 1)
net.ipv4.ip_forward = $forward_setting
net.ipv6.conf.all.forwarding = $forward_setting

# Disable IP Source Routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable ICMP Redirects (Sending and Receiving)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Mitigate IP Spoofing (Reverse Path Filtering)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log Martian Packets (Unroutable/Spoofed Addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# IPv6 Router Advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Process and Memory Protection
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.kexec_load_disabled = 1

# Filesystem Link Protections & Core Dumps
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
EOF

  if command -v sysctl >/dev/null 2>&1; then
    run_cmd sysctl --system || run_cmd sysctl -p "$SYSCTL_CONF"
  fi

  checkpoint sysctl
}
