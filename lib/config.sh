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
      --install-cloudflared)
        INSTALL_CLOUDFLARED="yes"
        shift
        ;;
      --ssh-public-key-file)
        SSH_PUBLIC_KEY_FILE="${2:?Missing value for --ssh-public-key-file}"
        shift 2
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
  --user NAME                   Admin user to create
  --ssh-port PORT               SSH port to configure
  --firewall-mode safe|traditional
  --install-basic-tools         Install basic utilities
  --no-basic-tools              Install only required packages
  --install-docker              Install Docker Engine from official apt repo
  --install-dokploy             Install Dokploy explicitly (implies Docker)
  --install-cloudflared         Install cloudflared from Cloudflare apt repo
  --ssh-public-key-file FILE    Public key file to seed authorized_keys
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

  is_yes "$INSTALL_BASIC_TOOLS" || is_no "$INSTALL_BASIC_TOOLS" || die "INSTALL_BASIC_TOOLS must be yes/no"
  is_yes "$INSTALL_DOCKER" || is_no "$INSTALL_DOCKER" || die "INSTALL_DOCKER must be yes/no"
  is_yes "$INSTALL_DOKPLOY" || is_no "$INSTALL_DOKPLOY" || die "INSTALL_DOKPLOY must be yes/no"
  is_yes "$INSTALL_CLOUDFLARED" || is_no "$INSTALL_CLOUDFLARED" || die "INSTALL_CLOUDFLARED must be yes/no"

  if is_yes "$INSTALL_CLOUDFLARED" && [[ -z "${CLOUDFLARED_TOKEN:-}" ]]; then
    die "CLOUDFLARED_TOKEN must be provided in environment for cloudflared service install"
  fi
}

show_plan() {
  cat <<EOF
Plan:
  Admin user:            $NEW_ADMIN_USER
  SSH port:              $SSH_PORT
  Firewall mode:         $FIREWALL_MODE
  Basic tools:           $INSTALL_BASIC_TOOLS
  Docker:                $INSTALL_DOCKER
  Dokploy:               $INSTALL_DOKPLOY
  Cloudflare Tunnel:     $INSTALL_CLOUDFLARED
  State dir:             $STATE_DIR
  Backup dir:            $SYSTEM_BACKUP_DIR
  Log dir:               $LOG_DIR

No changes were applied.
EOF
}

confirm_execution() {
  if [[ "$ASSUME_YES" == "yes" ]]; then
    return 0
  fi
  printf '\nThis will modify SSH, UFW, Fail2Ban and package configuration.\n'
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
INSTALL_CLOUDFLARED="$INSTALL_CLOUDFLARED"
ARCH="$ARCH"
DEB_ARCH="$DEB_ARCH"
EOF
}
