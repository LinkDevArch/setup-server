#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "Run as root: sudo bash rollback.sh" >&2; exit 1; }

STATE_DIR="${STATE_DIR:-/var/lib/vps-init-hardening}"
LOG_FILE="${LOG_FILE:-/var/log/vps-init-hardening/manual-rollback-$(date -u +%Y%m%dT%H%M%SZ).log}"

mkdir -p "$(dirname "$LOG_FILE")"

latest="$(find "$STATE_DIR" -maxdepth 1 -type f -name 'rollback-*.sh' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')"

if [[ -z "${latest:-}" ]]; then
  echo "No rollback script found in $STATE_DIR" >&2
  exit 1
fi

echo "Running rollback script: $latest"
LOG_FILE="$LOG_FILE" bash "$latest"
