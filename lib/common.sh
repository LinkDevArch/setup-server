#!/usr/bin/env bash

SCRIPT_NAME="vps-init-hardening"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE=""
ARCH=""
DEB_ARCH=""

red=$'\033[0;31m'
green=$'\033[0;32m'
yellow=$'\033[1;33m'
blue=$'\033[0;34m'
bold=$'\033[1m'
reset=$'\033[0m'

print_header() {
  printf '%s\n' "${bold}============================================================${reset}"
  printf '%s\n' "${bold} VPS Init Hardening - Ubuntu 24.04 LTS${reset}"
  printf '%s\n' "${bold}============================================================${reset}"
}

init_logging() {
  mkdir -p "$LOG_DIR"
  chmod 700 "$LOG_DIR"
  LOG_FILE="$LOG_DIR/run-$RUN_ID.log"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
}

log_line() {
  local level="$1"
  shift
  local message="$*"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '%s [%s] %s\n' "$ts" "$level" "$message" >> "$LOG_FILE"
  fi
  case "$level" in
    ERROR) printf '%s[%s]%s %s\n' "$red" "$level" "$reset" "$message" >&2 ;;
    WARN)  printf '%s[%s]%s %s\n' "$yellow" "$level" "$reset" "$message" >&2 ;;
    OK)    printf '%s[%s]%s %s\n' "$green" "$level" "$reset" "$message" ;;
    *)     printf '%s[%s]%s %s\n' "$blue" "$level" "$reset" "$message" ;;
  esac
}

download_gpg_key() {
  local url="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp "${dest}.tmp.XXXXXX")"
  run_cmd curl -fsSL "$url" -o "$tmp.asc"
  rm -f "$tmp"
  run_cmd gpg --dearmor -o "$tmp" "$tmp.asc"
  chmod a+r "$tmp"
  mv -f "$tmp" "$dest"
  rm -f "$tmp.asc"
}

log_info() { log_line INFO "$@"; }
log_warn() { log_line WARN "$@"; }
log_error() { log_line ERROR "$@"; }
log_ok() { log_line OK "$@"; }

die() {
  log_error "$*"
  if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
    log_error "--- Last 25 lines of execution log ($LOG_FILE) ---"
    tail -n 25 "$LOG_FILE" >&2 || true
    log_error "--- End of execution log snippet ---"
  fi
  if [[ "${ROLLBACK_READY:-no}" == "yes" ]]; then
    run_rollback
    log_error "Execution failed. Review log: $LOG_FILE"
    if [[ -n "${ROLLBACK_FILE:-}" ]]; then
      log_error "Manual rollback script retained at: $ROLLBACK_FILE"
    fi
  fi
  exit 1
}

run_cmd() {
  log_info "RUN: $*"
  "$@" >> "$LOG_FILE" 2>&1
}

run_cmd_secret() {
  local label="$1"
  shift
  log_info "RUN: $label"
  "$@" >> "$LOG_FILE" 2>&1
}

is_yes() {
  case "${1:-}" in
    yes|y|Y|true|TRUE|1) return 0 ;;
    *) return 1 ;;
  esac
}

is_no() {
  case "${1:-}" in
    no|n|N|false|FALSE|0) return 0 ;;
    *) return 1 ;;
  esac
}

atomic_write_file() {
  local target="$1"
  local mode="$2"
  local owner="$3"
  local group="$4"
  local tmp
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  cat > "$tmp"
  chown "$owner:$group" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$target"
}

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}
