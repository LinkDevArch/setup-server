#!/usr/bin/env bash

stage_docker() {
  if has_checkpoint docker; then
    log_info "Skipping Docker stage; checkpoint exists"
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
    log_info "Docker already installed and reachable"
    run_cmd usermod -aG docker "$NEW_ADMIN_USER"
    checkpoint docker
    return 0
  fi

  log_info "Installing Docker Engine from official Docker apt repository"
  export DEBIAN_FRONTEND=noninteractive
  backup_path /etc/apt/keyrings
  backup_path /etc/apt/sources.list.d

  run_cmd apt-get update
  run_cmd apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    download_gpg_key https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.gpg
  fi

  atomic_write_file /etc/apt/sources.list.d/docker.list 644 root root <<EOF
deb [arch=$DEB_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable
EOF

  add_rollback "remove docker apt source" "rm -f /etc/apt/sources.list.d/docker.list"
  run_cmd apt-get update
  run_cmd apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  run_cmd systemctl enable docker
  run_cmd systemctl start docker
  run_cmd usermod -aG docker "$NEW_ADMIN_USER"
  run_cmd docker version

  checkpoint docker
}
