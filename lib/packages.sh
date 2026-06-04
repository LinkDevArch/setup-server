#!/usr/bin/env bash

stage_system_packages() {
  if has_checkpoint packages; then
    log_info "Skipping packages stage; checkpoint exists"
    return 0
  fi

  log_info "Installing required system packages"
  export DEBIAN_FRONTEND=noninteractive
  run_cmd apt-get update

  local required=(ca-certificates gnupg lsb-release openssh-server sudo ufw fail2ban)
  local basic=(curl wget git htop tmux ncdu software-properties-common)
  if is_yes "$INSTALL_BASIC_TOOLS"; then
    run_cmd apt-get install -y "${required[@]}" "${basic[@]}"
  else
    run_cmd apt-get install -y "${required[@]}"
  fi

  checkpoint packages
}

