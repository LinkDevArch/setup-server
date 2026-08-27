#!/usr/bin/env bash

stage_system_packages() {
  if has_checkpoint packages; then
    log_info "Skipping packages stage; checkpoint exists"
    return 0
  fi

  log_info "Installing required system packages"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  run_cmd apt-get update -y
  run_cmd apt-get upgrade -y

  local required=(
    ca-certificates
    gnupg
    lsb-release
    openssh-server
    sudo
    ufw
    fail2ban
    python3-systemd
    unattended-upgrades
    needrestart
    update-notifier-common
    systemd-timesyncd
    auditd
    audispd-plugins
    libpam-pwquality
    iptables
    procps
  )

  local basic=(
    curl
    wget
    git
    htop
    tmux
    ncdu
    software-properties-common
    net-tools
    dnsutils
    jq
  )

  if is_yes "$INSTALL_BASIC_TOOLS"; then
    run_cmd apt-get install -y --no-install-recommends "${required[@]}" "${basic[@]}"
  else
    run_cmd apt-get install -y --no-install-recommends "${required[@]}"
  fi

  checkpoint packages
}
