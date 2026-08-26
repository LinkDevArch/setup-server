#!/usr/bin/env bash

validate_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo bash start.sh"
}

validate_ubuntu_2404() {
  [[ -r /etc/os-release ]] || die "/etc/os-release is missing"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Unsupported OS: ${ID:-unknown}. Ubuntu 24.04 LTS required"
  [[ "${VERSION_ID:-}" == "24.04" ]] || die "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Ubuntu 24.04 LTS required"
  log_ok "Ubuntu 24.04 detected"
}

detect_architecture() {
  ARCH="$(uname -m)"
  DEB_ARCH="$(dpkg --print-architecture)"
  case "$DEB_ARCH" in
    amd64|arm64|armhf) ;;
    *) die "Unsupported Debian architecture for this installer: $DEB_ARCH ($ARCH)" ;;
  esac
  log_ok "Architecture detected: $ARCH / $DEB_ARCH"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

