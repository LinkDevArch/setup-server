#!/usr/bin/env bash

stage_docker() {
  if has_checkpoint docker; then
    log_info "Skipping Docker stage; checkpoint exists"
    return 0
  fi

  log_info "Installing and hardening Docker Engine from official repository"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  backup_path /etc/apt/keyrings
  backup_path /etc/apt/sources.list.d
  backup_path /etc/docker

  run_cmd apt-get update -y
  run_cmd apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    download_gpg_key https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.gpg
  fi

  atomic_write_file /etc/apt/sources.list.d/docker.list 644 root root <<EOF
deb [arch=$DEB_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable
EOF

  add_rollback "remove docker apt source" "rm -f /etc/apt/sources.list.d/docker.list"
  run_cmd apt-get update -y
  run_cmd apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Apply Docker daemon hardening
  mkdir -p /etc/docker
  backup_path /etc/docker/daemon.json

  # Note: live-restore is strictly incompatible with Docker Swarm (used by Dokploy)
  if is_yes "$INSTALL_DOKPLOY"; then
    atomic_write_file /etc/docker/daemon.json 600 root root <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "userland-proxy": false
}
EOF
  else
    atomic_write_file /etc/docker/daemon.json 600 root root <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF
  fi

  # Apply UFW firewall protection against Docker port bypass
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    configure_docker_ufw_rules
    run_cmd ufw reload || true
  fi

  run_cmd systemctl enable docker
  run_cmd systemctl restart docker

  if is_yes "${ADD_USER_TO_DOCKER_GROUP:-yes}"; then
    log_info "Adding $NEW_ADMIN_USER to docker group"
    run_cmd usermod -aG docker "$NEW_ADMIN_USER"
  fi

  run_cmd docker version

  checkpoint docker
}
