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

  # Stop any conflicting web servers holding ports 80 or 443 (e.g. pre-installed apache2)
  for srv in apache2 nginx lighttpd; do
    if systemctl is-active --quiet "$srv" 2>/dev/null; then
      log_warn "Stopping conflicting web server ($srv) to free ports 80/443 for Dokploy Traefik"
      run_cmd systemctl stop "$srv" || true
      run_cmd systemctl disable "$srv" || true
    fi
  done

  # Open required Dokploy and Docker Swarm ports in UFW
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    log_info "Ensuring Dokploy and Swarm ports are permitted in firewall"
    run_cmd ufw allow 80/tcp comment "dokploy traefik http"
    run_cmd ufw allow 443/tcp comment "dokploy traefik https"
    run_cmd ufw allow "${DOKPLOY_PORT:-3000}/tcp" comment "dokploy dashboard"
    run_cmd ufw allow 2377/tcp comment "dokploy swarm cluster"
    run_cmd ufw allow 7946/tcp comment "dokploy swarm node"
    run_cmd ufw allow 7946/udp comment "dokploy swarm node"
    run_cmd ufw allow 4789/udp comment "dokploy swarm overlay"
  fi

  # Auto-detect local gateway IP for Swarm advertise address
  local adv_ip=""
  adv_ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')"
  if [[ -z "$adv_ip" ]]; then
    adv_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [[ -n "$adv_ip" ]]; then
    export ADVERTISE_ADDR="$adv_ip"
    log_info "Using advertise address for Dokploy Swarm: $adv_ip"
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
