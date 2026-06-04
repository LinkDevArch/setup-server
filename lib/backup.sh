#!/usr/bin/env bash

prepare_state_dirs() {
  mkdir -p "$STATE_DIR" "$SYSTEM_BACKUP_DIR" "$LOG_DIR"
  chmod 700 "$STATE_DIR" "$SYSTEM_BACKUP_DIR" "$LOG_DIR"
}

backup_path() {
  local path="$1"
  local label
  local dest
  label="$(printf '%s' "$path" | sed 's#/#_#g; s#^_##')"
  dest="$SYSTEM_BACKUP_DIR/$RUN_ID/$label"
  mkdir -p "$(dirname "$dest")"

  if [[ -e "$path" ]]; then
    mkdir -p "$SYSTEM_BACKUP_DIR/$RUN_ID"
    if [[ -d "$path" ]]; then
      cp -a "$path" "$dest"
    else
      cp -a "$path" "$dest"
    fi
    log_info "Backup created: $path -> $dest"
    add_rollback "restore $path" "if [[ -e '$dest' ]]; then rm -rf '$path'; cp -a '$dest' '$path'; fi"
  else
    log_info "Path does not exist before change: $path"
    add_rollback "remove newly created $path" "rm -rf '$path'"
  fi
}

