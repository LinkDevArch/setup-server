# Recovery Guide

Use this guide from the still-open root session if a new SSH login does not work or services need verification.

1. Check SSH syntax:

   ```bash
   sshd -t
   ```

2. Review the active hardening drop-in:

   ```bash
   cat /etc/ssh/sshd_config.d/00-vps-hardening.conf
   ```

3. Check SSH daemon / socket status (Ubuntu 24.04):

   ```bash
   # If running on default port 22
   systemctl status ssh.socket ssh.service --no-pager

   # If running on a custom port
   systemctl status ssh.service --no-pager
   ```

4. Restore the latest automatic backup manually if needed:

   ```bash
   ls -lah /var/backups/vps-init-hardening
   # Replace <RUN_ID> with the actual timestamp folder:
   cp -a /var/backups/vps-init-hardening/<RUN_ID>/etc_ssh_sshd_config /etc/ssh/sshd_config
   rm -rf /etc/ssh/sshd_config.d
   cp -a /var/backups/vps-init-hardening/<RUN_ID>/etc_ssh_sshd_config.d /etc/ssh/sshd_config.d
   sshd -t
   systemctl daemon-reload
   systemctl reload-or-restart ssh.service
   ```

5. If UFW blocked the selected port:

   ```bash
   ufw allow <SSH_PORT>/tcp
   ufw status verbose
   ```

6. If all else fails from the active root session, temporarily disable UFW:

   ```bash
   ufw disable
   ```

Re-enable UFW only after confirming the SSH port rule is present.
