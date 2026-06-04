#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/rollback.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/backup.sh"
source "$PROJECT_DIR/lib/validate.sh"
source "$PROJECT_DIR/lib/packages.sh"
source "$PROJECT_DIR/lib/users.sh"
source "$PROJECT_DIR/lib/firewall.sh"
source "$PROJECT_DIR/lib/ssh.sh"
source "$PROJECT_DIR/lib/fail2ban.sh"
source "$PROJECT_DIR/lib/docker.sh"
source "$PROJECT_DIR/lib/dokploy.sh"
source "$PROJECT_DIR/lib/cloudflared.sh"
source "$PROJECT_DIR/lib/postcheck.sh"

main() {
  bootstrap_config "$@"
  validate_root
  init_logging
  init_lock
  init_rollback
  reset_checkpoints_after_success
  trap 'on_error ${LINENO} "$BASH_COMMAND" "$?"' ERR
  trap 'cleanup_lock' EXIT

  print_header
  log_info "Log file: $LOG_FILE"

  validate_ubuntu_2404
  detect_architecture
  load_or_prompt_config
  validate_config

  if [[ "$DRY_RUN" == "yes" ]]; then
    show_plan
    exit 0
  fi

  confirm_execution
  prepare_state_dirs
  record_run_config

  stage_system_packages
  stage_admin_user
  stage_firewall
  stage_ssh_hardening
  stage_fail2ban

  if is_yes "$INSTALL_DOCKER" || is_yes "$INSTALL_DOKPLOY"; then
    stage_docker
  fi
  if is_yes "$INSTALL_DOKPLOY"; then
    stage_dokploy
  fi
  if is_yes "$INSTALL_CLOUDFLARED"; then
    stage_cloudflared
  fi

  post_install_checks
  mark_success
  print_summary
}

main "$@"
