#!/usr/bin/env bash

root_authorized_keys_source() {
  if [[ -n "$SSH_PUBLIC_KEY_FILE" ]]; then
    [[ -r "$SSH_PUBLIC_KEY_FILE" ]] || die "SSH public key file is not readable: $SSH_PUBLIC_KEY_FILE"
    printf '%s\n' "$SSH_PUBLIC_KEY_FILE"
    return 0
  fi

  [[ -s /root/.ssh/authorized_keys ]] || die "Missing /root/.ssh/authorized_keys. Add a public key first or pass --ssh-public-key-file"
  printf '%s\n' "/root/.ssh/authorized_keys"
}

validate_authorized_keys_file() {
  local file="$1"
  [[ -s "$file" ]] || die "authorized_keys source is empty: $file"
  if ! ssh-keygen -l -f "$file" >/dev/null 2>&1; then
    die "authorized_keys source does not contain a valid public key: $file"
  fi
}

stage_admin_user() {
  if has_checkpoint admin-user; then
    log_info "Skipping admin user stage; checkpoint exists"
    return 0
  fi

  local key_source
  key_source="$(root_authorized_keys_source)"
  validate_authorized_keys_file "$key_source"

  backup_path /etc/sudoers.d
  backup_path "/home/$NEW_ADMIN_USER/.ssh/authorized_keys"

  if id "$NEW_ADMIN_USER" >/dev/null 2>&1; then
    log_info "User already exists: $NEW_ADMIN_USER"
  else
    run_cmd useradd -m -s /bin/bash "$NEW_ADMIN_USER"
    add_rollback "delete created user $NEW_ADMIN_USER" "if id '$NEW_ADMIN_USER' >/dev/null 2>&1; then userdel -r '$NEW_ADMIN_USER' || true; fi"
  fi

  # Add admin user to administrative and logging groups
  run_cmd usermod -aG sudo "$NEW_ADMIN_USER"
  if getent group adm >/dev/null 2>&1; then
    run_cmd usermod -aG adm "$NEW_ADMIN_USER"
  fi
  if getent group systemd-journal >/dev/null 2>&1; then
    run_cmd usermod -aG systemd-journal "$NEW_ADMIN_USER"
  fi

  # Restrict home directory permissions
  chmod 700 "/home/$NEW_ADMIN_USER"

  local sudoers_file="/etc/sudoers.d/90-vps-init-$NEW_ADMIN_USER"
  atomic_write_file "$sudoers_file" 440 root root <<EOF
$NEW_ADMIN_USER ALL=(ALL) NOPASSWD:ALL
Defaults:$NEW_ADMIN_USER timestamp_timeout=15
EOF
  run_cmd visudo -cf "$sudoers_file"

  local ssh_dir="/home/$NEW_ADMIN_USER/.ssh"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  cp "$key_source" "$ssh_dir/authorized_keys"
  chown -R "$NEW_ADMIN_USER:$NEW_ADMIN_USER" "$ssh_dir"
  chmod 600 "$ssh_dir/authorized_keys"
  validate_authorized_keys_file "$ssh_dir/authorized_keys"

  checkpoint admin-user
}
