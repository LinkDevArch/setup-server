#!/usr/bin/env bash

CONFIG_FILE="$PROJECT_DIR/config/defaults.conf"
ASSUME_YES="no"
NONINTERACTIVE="no"
DRY_RUN="no"

bootstrap_config() {
  source "$PROJECT_DIR/config/defaults.conf"

  local args=("$@")
  local i=0
  while (( i < ${#args[@]} )); do
    if [[ "${args[$i]}" == "--config" ]]; then
      (( i + 1 < ${#args[@]} )) || die "Missing value for --config"
      CONFIG_FILE="${args[$((i + 1))]}"
      break
    fi
    ((i+=1))
  done

  if [[ "$CONFIG_FILE" != "$PROJECT_DIR/config/defaults.conf" ]]; then
    [[ -r "$CONFIG_FILE" ]] || die "Config file not readable: $CONFIG_FILE"
    source "$CONFIG_FILE"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        CONFIG_FILE="${2:?Missing value for --config}"
        shift 2
        ;;
      --user)
        NEW_ADMIN_USER="${2:?Missing value for --user}"
        shift 2
        ;;
      --ssh-port)
        SSH_PORT="${2:?Missing value for --ssh-port}"
        shift 2
        ;;
      --firewall-mode)
        FIREWALL_MODE="${2:?Missing value for --firewall-mode}"
        shift 2
        ;;
      --install-basic-tools)
        INSTALL_BASIC_TOOLS="yes"
        shift
        ;;
      --no-basic-tools)
        INSTALL_BASIC_TOOLS="no"
        shift
        ;;
      --install-docker)
        INSTALL_DOCKER="yes"
        shift
        ;;
      --install-dokploy)
        INSTALL_DOKPLOY="yes"
        INSTALL_DOCKER="yes"
        shift
        ;;
      --dokploy-port)
        DOKPLOY_PORT="${2:?Missing value for --dokploy-port}"
        shift 2
        ;;
      --install-cloudflared)
        INSTALL_CLOUDFLARED="yes"
        shift
        ;;
      --ssh-public-key-file)
        SSH_PUBLIC_KEY_FILE="${2:?Missing value for --ssh-public-key-file}"
        shift 2
        ;;
      --no-sysctl)
        ENABLE_SYSCTL_HARDENING="no"
        shift
        ;;
      --no-updates)
        ENABLE_SECURITY_UPDATES="no"
        shift
        ;;
      --no-auditd)
        ENABLE_AUDITD="no"
        shift
        ;;
      --no-system-hardening)
        ENABLE_SYSTEM_HARDENING="no"
        shift
        ;;
      --no-timesync)
        ENABLE_TIMESYNC="no"
        shift
        ;;
      --no-docker-ufw-fix)
        DOCKER_UFW_FIX="no"
        shift
        ;;
      --no-docker-group)
        ADD_USER_TO_DOCKER_GROUP="no"
        shift
        ;;
      --yes|-y)
        ASSUME_YES="yes"
        NONINTERACTIVE="yes"
        shift
        ;;
      --dry-run)
        DRY_RUN="yes"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage
        exit 2
        ;;
    esac
  done
}

usage() {
  cat <<'EOF'
Usage: sudo bash start.sh [options]

Options:
  --config FILE                 Load configuration overrides
  --user NAME                   Admin user to create (default: deployer)
  --ssh-port PORT               SSH port to configure (default: 22)
  --firewall-mode MODE          Firewall mode: safe|traditional (default: safe)
  --install-basic-tools         Install basic CLI utilities
  --no-basic-tools              Install only minimal required packages
  --install-docker              Install and harden Docker Engine
  --install-dokploy             Install Dokploy deployment platform (implies Docker)
  --dokploy-port PORT           Dokploy dashboard port for UFW in traditional mode (default: 3000)
  --install-cloudflared         Install Cloudflare Tunnel from official apt repo
  --ssh-public-key-file FILE    Public key file to seed authorized_keys
  --no-sysctl                   Disable kernel/network sysctl hardening
  --no-updates                  Disable unattended security updates
  --no-auditd                   Disable auditd logging framework
  --no-system-hardening         Disable modprobe blacklist and system limits
  --no-timesync                 Disable systemd-timesyncd NTP configuration
  --no-docker-ufw-fix           Disable Docker UFW bypass protection
  --no-docker-group             Do not add admin user to docker group
  --yes, -y                     Non-interactive mode with configured defaults
  --dry-run                     Show planned changes and exit
  --help, -h                    Show this help
EOF
}

prompt_default() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name}"
  local answer=""
  read -r -p "$prompt [$current]: " answer
  if [[ -n "$answer" ]]; then
    printf -v "$var_name" '%s' "$answer"
  fi
}

prompt_yes_no() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name}"
  local answer=""
  read -r -p "$prompt [$current]: " answer
  if [[ -n "$answer" ]]; then
    case "$answer" in
      y|Y|yes|YES|s|S|si|SI) printf -v "$var_name" 'yes' ;;
      n|N|no|NO) printf -v "$var_name" 'no' ;;
      *) die "Invalid yes/no answer for $var_name: $answer" ;;
    esac
  fi
}

prompt_secret_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name:-}"
  local answer=""

  if [[ -n "$current" ]]; then
    return 0
  fi

  read -r -s -p "$prompt: " answer
  printf '\n'
  if [[ -n "$answer" ]]; then
    printf -v "$var_name" '%s' "$answer"
  fi
}

load_or_prompt_config() {
  if [[ "$NONINTERACTIVE" == "yes" ]]; then
    return 0
  fi

  prompt_default NEW_ADMIN_USER "Admin user"
  prompt_default SSH_PORT "SSH port"
  prompt_default FIREWALL_MODE "Firewall mode (safe|traditional)"
  prompt_yes_no INSTALL_BASIC_TOOLS "Install basic tools"
  prompt_yes_no INSTALL_DOCKER "Install Docker"
  prompt_yes_no INSTALL_DOKPLOY "Install Dokploy explicitly"
  prompt_yes_no INSTALL_CLOUDFLARED "Install Cloudflare Tunnel"

  if is_yes "$INSTALL_DOKPLOY"; then
    INSTALL_DOCKER="yes"
  fi

  if is_yes "$INSTALL_CLOUDFLARED"; then
    prompt_secret_if_empty CLOUDFLARED_TOKEN "Cloudflare Tunnel token"
  fi

  # Check if SSH public key exists for the admin user
  local has_key="no"
  if [[ -n "${SSH_PUBLIC_KEY_FILE:-}" && -s "$SSH_PUBLIC_KEY_FILE" ]]; then
    has_key="yes"
  elif [[ -s /root/.ssh/authorized_keys ]]; then
    has_key="yes"
  fi

  if [[ "$has_key" == "no" ]]; then
    printf '\n%s\n' "${yellow}[!] No SSH public key found in /root/.ssh/authorized_keys.${reset}"
    printf '%s\n' "Because root and password logins will be disabled, an SSH public key is required to avoid lockout."
    printf '%s\n' "Please paste your public key (e.g. from ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub on your PC):"
    local pasted_key=""
    read -r -p "SSH Public Key: " pasted_key
    if [[ -n "$pasted_key" ]]; then
      local tmp_key
      tmp_key="$(mktemp)"
      printf '%s\n' "$pasted_key" > "$tmp_key"
      if command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -l -f "$tmp_key" >/dev/null 2>&1; then
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        printf '%s\n' "$pasted_key" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        log_ok "SSH public key saved to /root/.ssh/authorized_keys"
      else
        rm -f "$tmp_key"
        die "The pasted key is not a valid SSH public key. Format: ssh-ed25519 AAAAC3... or ssh-rsa AAAAB3..."
      fi
      rm -f "$tmp_key"
    else
      die "An SSH public key is mandatory to prevent permanent server lockout"
    fi
  fi
}

validate_config() {
  [[ "$NEW_ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid user name: $NEW_ADMIN_USER"
  [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT must be numeric"
  (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || die "SSH_PORT out of range: $SSH_PORT"
  [[ "$SSH_PORT" != "0" ]] || die "SSH_PORT cannot be 0"

  case "$FIREWALL_MODE" in
    safe|traditional) ;;
    *) die "FIREWALL_MODE must be safe or traditional" ;;
  esac

  if [[ -n "${DOKPLOY_PORT:-}" ]]; then
    [[ "$DOKPLOY_PORT" =~ ^[0-9]+$ ]] || die "DOKPLOY_PORT must be numeric"
    (( DOKPLOY_PORT >= 1 && DOKPLOY_PORT <= 65535 )) || die "DOKPLOY_PORT out of range: $DOKPLOY_PORT"
  fi

  is_yes "$INSTALL_BASIC_TOOLS" || is_no "$INSTALL_BASIC_TOOLS" || die "INSTALL_BASIC_TOOLS must be yes/no"
  is_yes "$INSTALL_DOCKER" || is_no "$INSTALL_DOCKER" || die "INSTALL_DOCKER must be yes/no"
  is_yes "$INSTALL_DOKPLOY" || is_no "$INSTALL_DOKPLOY" || die "INSTALL_DOKPLOY must be yes/no"
  is_yes "$INSTALL_CLOUDFLARED" || is_no "$INSTALL_CLOUDFLARED" || die "INSTALL_CLOUDFLARED must be yes/no"
  is_yes "$ENABLE_SYSCTL_HARDENING" || is_no "$ENABLE_SYSCTL_HARDENING" || die "ENABLE_SYSCTL_HARDENING must be yes/no"
  is_yes "$ENABLE_SECURITY_UPDATES" || is_no "$ENABLE_SECURITY_UPDATES" || die "ENABLE_SECURITY_UPDATES must be yes/no"
  is_yes "$ENABLE_AUDITD" || is_no "$ENABLE_AUDITD" || die "ENABLE_AUDITD must be yes/no"
  is_yes "$ENABLE_SYSTEM_HARDENING" || is_no "$ENABLE_SYSTEM_HARDENING" || die "ENABLE_SYSTEM_HARDENING must be yes/no"
  is_yes "$ENABLE_TIMESYNC" || is_no "$ENABLE_TIMESYNC" || die "ENABLE_TIMESYNC must be yes/no"
  is_yes "$DOCKER_UFW_FIX" || is_no "$DOCKER_UFW_FIX" || die "DOCKER_UFW_FIX must be yes/no"
  is_yes "$ADD_USER_TO_DOCKER_GROUP" || is_no "$ADD_USER_TO_DOCKER_GROUP" || die "ADD_USER_TO_DOCKER_GROUP must be yes/no"

  if is_yes "$INSTALL_CLOUDFLARED" && [[ -z "${CLOUDFLARED_TOKEN:-}" ]]; then
    if [[ "$NONINTERACTIVE" == "yes" ]]; then
      die "CLOUDFLARED_TOKEN must be provided in environment for non-interactive cloudflared install"
    fi
    die "Cloudflare Tunnel token is required when Cloudflare Tunnel is selected"
  fi

  if [[ "$DRY_RUN" != "yes" ]]; then
    if [[ -n "${SSH_PUBLIC_KEY_FILE:-}" ]]; then
      [[ -s "$SSH_PUBLIC_KEY_FILE" ]] || die "SSH public key file is empty or not readable: $SSH_PUBLIC_KEY_FILE"
    else
      [[ -s /root/.ssh/authorized_keys ]] || die "Missing /root/.ssh/authorized_keys. Add a public key first or pass --ssh-public-key-file"
    fi
  fi
}

show_plan() {
  cat <<EOF
Plan:
  Admin user:                 $NEW_ADMIN_USER
  SSH port:                   $SSH_PORT
  Firewall mode:              $FIREWALL_MODE
  Basic tools:                $INSTALL_BASIC_TOOLS
  Kernel sysctl hardening:    $ENABLE_SYSCTL_HARDENING
  Security updates:           $ENABLE_SECURITY_UPDATES
  System hardening (modprobe):$ENABLE_SYSTEM_HARDENING
  Time sync (NTP):            $ENABLE_TIMESYNC
  Auditd framework (CIS):     $ENABLE_AUDITD
  Docker:                     $INSTALL_DOCKER
  Docker UFW protection:      $DOCKER_UFW_FIX
  Add admin to docker group:  $ADD_USER_TO_DOCKER_GROUP
  Dokploy:                    $INSTALL_DOKPLOY
  Cloudflare Tunnel:          $INSTALL_CLOUDFLARED
  State dir:                  $STATE_DIR
  Backup dir:                 $SYSTEM_BACKUP_DIR
  Log dir:                    $LOG_DIR

No changes were applied.
EOF
}

confirm_execution() {
  if [[ "$ASSUME_YES" == "yes" ]]; then
    return 0
  fi
  printf '\nThis will modify SSH, UFW, Kernel sysctl, Fail2Ban and system configuration.\n'
  read -r -p "Continue? [yes/NO]: " answer
  [[ "$answer" == "yes" ]] || die "Aborted by user"
}

record_run_config() {
  local cfg="$STATE_DIR/last-run.conf"
  atomic_write_file "$cfg" 600 root root <<EOF
RUN_ID="$RUN_ID"
NEW_ADMIN_USER="$NEW_ADMIN_USER"
SSH_PORT="$SSH_PORT"
FIREWALL_MODE="$FIREWALL_MODE"
INSTALL_BASIC_TOOLS="$INSTALL_BASIC_TOOLS"
INSTALL_DOCKER="$INSTALL_DOCKER"
INSTALL_DOKPLOY="$INSTALL_DOKPLOY"
DOKPLOY_PORT="$DOKPLOY_PORT"
INSTALL_CLOUDFLARED="$INSTALL_CLOUDFLARED"
ENABLE_SYSCTL_HARDENING="$ENABLE_SYSCTL_HARDENING"
ENABLE_SECURITY_UPDATES="$ENABLE_SECURITY_UPDATES"
ENABLE_AUDITD="$ENABLE_AUDITD"
ENABLE_SYSTEM_HARDENING="$ENABLE_SYSTEM_HARDENING"
ENABLE_TIMESYNC="$ENABLE_TIMESYNC"
DOCKER_UFW_FIX="$DOCKER_UFW_FIX"
ADD_USER_TO_DOCKER_GROUP="$ADD_USER_TO_DOCKER_GROUP"
ARCH="$ARCH"
DEB_ARCH="$DEB_ARCH"
EOF
}
