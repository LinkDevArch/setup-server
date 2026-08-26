#!/usr/bin/env bash

ROLLBACK_DIR=""
ROLLBACK_FILE=""
ROLLBACK_READY="no"
ROLLBACK_STEP_COUNTER=0
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
  flock -u 9 2>/dev/null || true
}

init_rollback() {
  mkdir -p "$STATE_DIR"
  ROLLBACK_DIR="$STATE_DIR/rollback-$RUN_ID.d"
  ROLLBACK_FILE="$STATE_DIR/rollback-$RUN_ID.sh"
  mkdir -p "$ROLLBACK_DIR"
  chmod 700 "$ROLLBACK_DIR"

  cat > "$ROLLBACK_FILE" <<EOF
#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="\${LOG_FILE:-/tmp/vps-init-rollback.log}"
log() {
  printf '%s [ROLLBACK] %s\n' "\$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "\$*" | tee -a "\$LOG_FILE" >&2
}

DIR="$ROLLBACK_DIR"

if [[ ! -d "\$DIR" ]]; then
  log "Rollback steps directory not found: \$DIR"
  exit 1
fi

log "Starting rollback execution from: \$DIR"
errors=0

# Execute steps in reverse numerical order (LIFO)
while IFS= read -r step_file; do
  [[ -n "\$step_file" && -f "\$step_file" ]] || continue
  log "Executing rollback step: \$(basename "\$step_file")"
  if bash "\$step_file"; then
    log "Step completed successfully: \$(basename "\$step_file")"
  else
    log "WARNING: Step reported error: \$(basename "\$step_file") (continuing remaining steps)"
    errors=\$((errors + 1))
  fi
done < <(find "\$DIR" -maxdepth 1 -name '*.step' | sort -r)

if (( errors > 0 )); then
  log "Rollback completed with \$errors warning(s). Inspect \$LOG_FILE"
  exit 1
else
  log "Rollback completed successfully"
fi
EOF

  chmod 700 "$ROLLBACK_FILE"
  chown root:root "$ROLLBACK_FILE" 2>/dev/null || true
  ROLLBACK_READY="yes"
}

add_rollback() {
  local label="$1"
  local command="$2"

  if [[ -z "${ROLLBACK_DIR:-}" || ! -d "$ROLLBACK_DIR" ]]; then
    return 0
  fi

  ROLLBACK_STEP_COUNTER=$((ROLLBACK_STEP_COUNTER + 1))
  local step_filename
  step_filename="$(printf '%05d.step' "$ROLLBACK_STEP_COUNTER")"
  local step_path="$ROLLBACK_DIR/$step_filename"

  cat > "$step_path" <<EOF
#!/usr/bin/env bash
# Label: $label
printf '%s [ROLLBACK-ACTION] %s\n' "\$(date -u '+%Y-%m-%dT%H:%M:%SZ')" $(printf '%q' "$label")
$command
EOF

  chmod 700 "$step_path"
  chown root:root "$step_path" 2>/dev/null || true

  log_info "Rollback registered (#$ROLLBACK_STEP_COUNTER): $label"
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
  if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
    log_error "--- Last 25 lines of execution log ($LOG_FILE) ---"
    tail -n 25 "$LOG_FILE" >&2 || true
    log_error "--- End of execution log snippet ---"
  fi
  run_rollback
  log_error "Execution failed. Review full log: $LOG_FILE"
  if [[ -n "${ROLLBACK_FILE:-}" && -f "$ROLLBACK_FILE" ]]; then
    log_error "Manual rollback script retained at: $ROLLBACK_FILE"
  fi
  exit "$status"
}

run_rollback() {
  if [[ "${IN_ROLLBACK:-no}" == "yes" ]]; then
    return 0
  fi
  IN_ROLLBACK="yes"

  if [[ -n "${ROLLBACK_FILE:-}" && -s "$ROLLBACK_FILE" ]]; then
    log_warn "Starting rollback in reverse registration order"
    if LOG_FILE="$LOG_FILE" bash "$ROLLBACK_FILE"; then
      log_warn "Rollback completed"
    else
      log_error "Rollback had warnings/errors. Inspect $LOG_FILE and $ROLLBACK_FILE"
    fi
  else
    log_warn "No rollback actions registered"
  fi
}

mark_success() {
  touch "$STATE_DIR/success"
  if [[ -n "${ROLLBACK_FILE:-}" && -f "$ROLLBACK_FILE" ]]; then
    rm -f "$ROLLBACK_FILE"
  fi
  if [[ -n "${ROLLBACK_DIR:-}" && -d "$ROLLBACK_DIR" ]]; then
    rm -rf "$ROLLBACK_DIR"
  fi
  log_ok "All stages completed"
}
