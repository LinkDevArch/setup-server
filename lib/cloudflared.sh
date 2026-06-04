#!/usr/bin/env bash

stage_cloudflared() {
  if has_checkpoint cloudflared; then
    log_info "Skipping cloudflared stage; checkpoint exists"
    return 0
  fi

  log_info "Installing cloudflared from Cloudflare apt repository"
  export DEBIAN_FRONTEND=noninteractive
  backup_path /etc/apt/keyrings
  backup_path /etc/apt/sources.list.d

  run_cmd apt-get update
  run_cmd apt-get install -y curl gnupg ca-certificates
  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/cloudflare-main.gpg ]]; then
    download_gpg_key https://pkg.cloudflare.com/cloudflare-main.gpg /etc/apt/keyrings/cloudflare-main.gpg
  fi

  atomic_write_file /etc/apt/sources.list.d/cloudflared.list 644 root root <<EOF
deb [arch=$DEB_ARCH signed-by=/etc/apt/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main
EOF

  add_rollback "remove cloudflared apt source" "rm -f /etc/apt/sources.list.d/cloudflared.list"
  run_cmd apt-get update
  run_cmd apt-get install -y cloudflared
  run_cmd cloudflared version

  if systemctl list-unit-files cloudflared.service >/dev/null 2>&1; then
    log_warn "Existing cloudflared service found; replacing service registration"
    run_cmd cloudflared service uninstall || true
  fi

  run_cmd_secret "cloudflared service install <redacted-token>" cloudflared service install "$CLOUDFLARED_TOKEN"
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable cloudflared
  run_cmd systemctl start cloudflared
  run_cmd systemctl is-active cloudflared

  checkpoint cloudflared
}
