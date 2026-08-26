#!/usr/bin/env bash

stage_firewall() {
  if has_checkpoint firewall; then
    log_info "Skipping firewall stage; checkpoint exists"
    return 0
  fi

  log_info "Configuring UFW (Uncomplicated Firewall) with rate limiting and leak prevention"
  backup_path /etc/ufw
  backup_path /etc/default/ufw

  # Ensure IPv6 is enabled in UFW configuration
  if [[ -f /etc/default/ufw ]]; then
    sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw || true
  fi

  if ! ufw status 2>/dev/null | grep -q "Status: active"; then
    add_rollback "disable UFW if this run enabled it" "ufw --force disable >/dev/null 2>&1 || true"
  fi

  # Default security policies
  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing

  # Rate limit SSH to prevent brute force at the firewall layer
  run_cmd ufw limit "$SSH_PORT/tcp" comment "vps-init ssh rate-limited"

  if [[ "$FIREWALL_MODE" == "traditional" ]]; then
    run_cmd ufw allow 80/tcp comment "vps-init http"
    run_cmd ufw allow 443/tcp comment "vps-init https"

    if is_yes "$INSTALL_DOKPLOY" && [[ -n "${DOKPLOY_PORT:-}" ]]; then
      run_cmd ufw allow "$DOKPLOY_PORT/tcp" comment "vps-init dokploy dashboard"
    fi
  fi

  # Apply Docker UFW bypass protection if Docker is enabled
  if is_yes "$INSTALL_DOCKER" || is_yes "$INSTALL_DOKPLOY" || command -v docker >/dev/null 2>&1; then
    configure_docker_ufw_rules
  fi

  run_cmd ufw logging low
  run_cmd ufw --force enable
  run_cmd ufw status verbose

  checkpoint firewall
}

configure_docker_ufw_rules() {
  if ! is_yes "${DOCKER_UFW_FIX:-yes}"; then
    log_info "Docker UFW bypass fix disabled by configuration"
    return 0
  fi

  local after_rules="/etc/ufw/after.rules"
  [[ -f "$after_rules" ]] || return 0

  if grep -q "BEGIN UFW AND DOCKER" "$after_rules"; then
    log_info "Docker UFW protection already present in $after_rules"
    return 0
  fi

  log_info "Integrating Docker UFW bypass protection in $after_rules"
  backup_path "$after_rules"

  cat >> "$after_rules" <<'EOF'

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
EOF
}
