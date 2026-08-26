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
    cp -a "$path" "$dest"
    log_info "Backup created: $path -> $dest"
    if [[ -d "$dest" ]]; then
      add_rollback "restore directory $path" "if [[ -d '$dest' ]]; then rm -rf '$path'; mkdir -p '$path'; cp -a '$dest/.' '$path/'; fi"
    else
      add_rollback "restore file $path" "if [[ -f '$dest' ]]; then mkdir -p '$(dirname "$path")'; cp -a '$dest' '$path'; fi"
    fi
  else
    log_info "Path does not exist before change: $path"
    add_rollback "remove newly created $path" "if [[ -e '$path' ]]; then rm -rf '$path'; fi"
  fi
}
