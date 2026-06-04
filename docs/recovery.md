# Recovery Guide

Use this guide from the still-open root session if a new SSH login does not work.

1. Check SSH syntax:

   ```bash
   sshd -t
   ```

2. Review the active hardening drop-in:

   ```bash
   cat /etc/ssh/sshd_config.d/99-vps-hardening.conf
   ```

3. Restore the latest automatic backup manually if needed:

   ```bash
   ls -lah /var/backups/vps-init-hardening
   cp -a /var/backups/vps-init-hardening/<RUN_ID>/etc_ssh_sshd_config /etc/ssh/sshd_config
   rm -rf /etc/ssh/sshd_config.d
   cp -a /var/backups/vps-init-hardening/<RUN_ID>/etc_ssh_sshd_config.d /etc/ssh/sshd_config.d
   sshd -t
   systemctl reload-or-restart ssh.service
   ```

4. If UFW blocked the selected port:

   ```bash
   ufw allow <SSH_PORT>/tcp
   ufw status verbose
   ```

5. If all else fails from the active root session, temporarily disable UFW:

   ```bash
   ufw disable
   ```

Re-enable UFW only after confirming the SSH port rule is present.

