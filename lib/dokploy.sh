#!/usr/bin/env bash

stage_dokploy() {
  if has_checkpoint dokploy; then
    log_info "Skipping Dokploy stage; checkpoint exists"
    return 0
  fi

  log_info "Installing Dokploy deployment manager"
  require_cmd docker

  if ! systemctl is-active --quiet docker; then
    run_cmd systemctl start docker
  fi

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Eq '^dokploy$|dokploy'; then
    log_info "Dokploy appears to be installed already"
    checkpoint dokploy
    return 0
  fi

  local install_script="/tmp/dokploy-install-$RUN_ID.sh"
  run_cmd curl -fsSL https://dokploy.com/install.sh -o "$install_script"
  [[ -s "$install_script" ]] || die "Failed to download Dokploy installer or downloaded file is empty"
  chmod 700 "$install_script"

  log_info "Executing official Dokploy installer"
  run_cmd bash "$install_script"
  rm -f "$install_script"

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -Eq '^dokploy$|dokploy'; then
    log_ok "Dokploy container detected and running"
  else
    log_warn "Dokploy installer completed; container may still be initializing in background"
  fi

  checkpoint dokploy
}
