#!/usr/bin/env bash

stage_firewall() {
  if has_checkpoint firewall; then
    log_info "Skipping firewall stage; checkpoint exists"
    return 0
  fi

  log_info "Configuring UFW"
  backup_path /etc/ufw

  if ! ufw status | grep -q "Status: active"; then
    add_rollback "disable UFW if this run enabled it" "ufw --force disable >/dev/null 2>&1 || true"
  fi

  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing
  run_cmd ufw allow "$SSH_PORT/tcp" comment "vps-init ssh"

  if [[ "$FIREWALL_MODE" == "traditional" ]]; then
    run_cmd ufw allow 80/tcp comment "vps-init http"
    run_cmd ufw allow 443/tcp comment "vps-init https"
  fi

  run_cmd ufw --force enable
  run_cmd ufw status verbose

  checkpoint firewall
}
