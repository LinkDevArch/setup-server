#!/usr/bin/env bash

ROLLBACK_FILE=""
LOCK_FD=9

init_lock() {
  mkdir -p "$STATE_DIR"
  exec 9>"$STATE_DIR/lock"
  if ! flock -n 9; then
    die "Another $SCRIPT_NAME run is already active"
  fi
}

reset_checkpoints_after_success() {
  if [[ -f "$STATE_DIR/success" ]]; then
    log_info "Previous successful run detected; clearing checkpoints so current configuration is reconciled"
    rm -rf "$STATE_DIR/checkpoints"
    rm -f "$STATE_DIR/success"
  fi
}

cleanup_lock() {
  flock -u 9 || true
}

init_rollback() {
  mkdir -p "$STATE_DIR"
  ROLLBACK_FILE="$STATE_DIR/rollback-$RUN_ID.sh"
  atomic_write_file "$ROLLBACK_FILE" 700 root root <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
LOG_FILE="${LOG_FILE:-/tmp/vps-init-rollback.log}"
log() { printf '%s [ROLLBACK] %s\n' "\$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "\$*" | tee -a "\$LOG_FILE" >&2; }
EOF
}

add_rollback() {
  local label="$1"
  local command="$2"
  local tmp="${ROLLBACK_FILE}.tmp"
  {
    sed '1,/^log()/!d' "$ROLLBACK_FILE"
    printf '\nlog %q\n%s\n' "$label" "$command"
    sed '1,/^log()/d' "$ROLLBACK_FILE"
  } > "$tmp"
  chmod 700 "$tmp"
  chown root:root "$tmp"
  mv -f "$tmp" "$ROLLBACK_FILE"
  log_info "Rollback registered: $label"
}

checkpoint() {
  local name="$1"
  mkdir -p "$STATE_DIR/checkpoints"
  touch "$STATE_DIR/checkpoints/$name"
  log_ok "Checkpoint completed: $name"
}

has_checkpoint() {
  [[ -f "$STATE_DIR/checkpoints/$1" ]]
}

on_error() {
  local line="$1"
  local cmd="$2"
  local status="$3"
  trap - ERR
  log_error "Failure at line $line while running: $cmd (exit $status)"
  run_rollback
  log_error "Execution failed. Review log: $LOG_FILE"
  log_error "Manual rollback script retained at: $ROLLBACK_FILE"
  exit "$status"
}

run_rollback() {
  if [[ -n "${ROLLBACK_FILE:-}" && -s "$ROLLBACK_FILE" ]]; then
    log_warn "Starting rollback in reverse registration order"
    if LOG_FILE="$LOG_FILE" bash "$ROLLBACK_FILE"; then
      log_warn "Rollback completed"
    else
      log_error "Rollback had errors. Inspect $LOG_FILE and $ROLLBACK_FILE"
    fi
  else
    log_warn "No rollback actions registered"
  fi
}

mark_success() {
  touch "$STATE_DIR/success"
  rm -f "$ROLLBACK_FILE"
  log_ok "All stages completed"
}
