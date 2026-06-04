#!/usr/bin/env bash

stage_dokploy() {
  if has_checkpoint dokploy; then
    log_info "Skipping Dokploy stage; checkpoint exists"
    return 0
  fi

  log_info "Installing Dokploy explicitly"
  require_cmd docker

  local install_script="/tmp/dokploy-install-$RUN_ID.sh"
  run_cmd curl -fsSL https://dokploy.com/install.sh -o "$install_script"
  chmod 700 "$install_script"

  if grep -Eq 'curl[[:space:]].*\|[[:space:]]*(sh|bash)|wget[[:space:]].*\|[[:space:]]*(sh|bash)' "$install_script"; then
    die "Dokploy installer contains nested pipe-to-shell pattern; aborting for audit"
  fi

  run_cmd bash "$install_script"
  rm -f "$install_script"

  if docker ps --format '{{.Names}}' | grep -Eq '^dokploy$|dokploy'; then
    log_ok "Dokploy container detected"
  else
    log_warn "Dokploy command completed but container name was not detected; check Docker services"
  fi

  checkpoint dokploy
}

