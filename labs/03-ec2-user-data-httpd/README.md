# EC2 user data: provision Apache on Amazon Linux 2023

## Goal

Use EC2 user data to prepare an Amazon Linux 2023 instance at first boot, then troubleshoot the result through `cloud-init` evidence instead of changing commands at random.

## Environment

- Amazon EC2 instance running Amazon Linux 2023
- An EC2 security group that permits only the required inbound HTTP traffic for the test
- EC2 user data configured at launch time

## What I built

[`scripts/user-data-httpd.sh`](scripts/user-data-httpd.sh) installs Apache (`httpd`), writes a simple local landing page, starts the service, and enables it for future boots.

Paste the file contents into the EC2 **User data** field before launching a test instance.

```bash
#!/bin/bash
set -euo pipefail

dnf install -y httpd
printf '%s\n' 'Provisioned by EC2 user data' > /var/www/html/index.html
systemctl enable --now httpd
```

The script has a shebang, avoids interactive prompts, and does not use `sudo` because EC2 user-data scripts run as root by default.

## Verification

After the instance has finished its status checks and user-data tasks:

```bash
sudo systemctl status httpd --no-pager
curl -I http://localhost
sudo tail -n 80 /var/log/cloud-init-output.log
```

Then test HTTP reachability from the intended client only after checking the relevant security-group rule.

```text
EC2 launch
  ↓
cloud-init runs user data
  ↓
dnf installs httpd
  ↓
systemd starts and enables httpd
  ↓
local curl check
  ↓
security-group and browser test
```

## Troubleshooting notes

When the web page is not reachable, I check in this order:

1. Is the instance running and are its status checks healthy?
2. Does the security group permit the intended inbound TCP port 80 source?
3. Is `httpd` installed, active, and listening locally?
4. What is the first meaningful error in `/var/log/cloud-init-output.log`?

```bash
cat /etc/os-release
rpm -q httpd
sudo systemctl status httpd --no-pager
sudo less /var/log/cloud-init-output.log
sudo less /var/log/cloud-init.log
```

One failure I learned to recognize is an incorrect package name. `dnf install HTTP` does not install Apache on Amazon Linux. The correct package is `httpd`. If installation fails, `systemctl` cannot start a service that does not exist.

Changing the displayed user-data text after launch does not make it run again. Test a corrected script on a newly launched disposable instance, or use a deliberate cloud-init re-execution process only when you understand the consequences.

## What I learned

- User data is good for predictable first-boot configuration.
- User data is not the first choice for changing an existing fleet; Systems Manager Run Command is a better fit for that.
- Successful package installation is separate from starting a service, enabling it at boot, and allowing network reachability.
- Logs are evidence. They are faster and safer than guessing.

## Security and cleanup

- Do not put credentials, private keys, API tokens, or database passwords in user data.
- Restrict the HTTP security-group source to the smallest range needed for the test.
- User-data output and files may be root-owned. Adjust ownership only when a non-root user actually needs access.
- Terminate the test instance and remove temporary security-group rules when finished.

## Reference

- [AWS EC2 user data for Linux instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
