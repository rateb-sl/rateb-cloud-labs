# EC2 user data: first-boot Apache provisioning

## Goal

Use EC2 user data to configure an Amazon Linux 2023 instance at first boot, then troubleshoot the result through cloud-init and service evidence.

## Environment

- EC2 instance running Amazon Linux 2023
- Security group permitting only the intended HTTP test traffic
- User data configured at launch

## Architecture

```text
EC2 launch
  → cloud-init executes user data as root
  → dnf installs httpd
  → page is written to the document root
  → systemd starts and enables httpd
  → local service check
  → external HTTP path check
```

User data solves first-boot configuration. It is not the general tool for changing an existing fleet; Systems Manager is a better operational surface for that.

## Implementation

### 1. Provision the first boot

[`scripts/user-data-httpd.sh`](scripts/user-data-httpd.sh) contains the reference script:

```bash
#!/bin/bash
set -euo pipefail

dnf install -y httpd
printf '%s\n' 'Provisioned by EC2 user data' > /var/www/html/index.html
systemctl enable --now httpd
```

The shebang selects Bash, `set -euo pipefail` prevents silent continuation, and no `sudo` is needed because user data runs as root.

### 2. Verify the host locally

```bash
sudo systemctl status httpd --no-pager
curl -I http://localhost
sudo tail -n 80 /var/log/cloud-init-output.log
```

This proves the package, service, local listener, and provisioning log separately. It does not prove that an external client can reach the instance.

### 3. Verify the public path

Only after confirming the security-group rule, test from the intended client:

```bash
curl -I --max-time 15 http://<public-ip-or-dns>
```

The full path requires a running instance, public addressing, routing, security-group permission, a listening service, and the correct document root.

## Failure boundaries

Check in dependency order:

1. Instance status checks
2. Security-group TCP/80 rule
3. `httpd` installation and service state
4. Listener on the host
5. First meaningful cloud-init error

```bash
cat /etc/os-release
rpm -q httpd
sudo systemctl status httpd --no-pager
sudo less /var/log/cloud-init-output.log
sudo less /var/log/cloud-init.log
```

`dnf install HTTP` is not equivalent to installing Apache on Amazon Linux; the package is `httpd`. Changing the user-data field after launch does not automatically rerun it.

## Cleanup

- Never put credentials, private keys, API tokens, or database passwords in user data.
- Restrict the HTTP source range to the smallest range needed.
- Terminate the test instance and remove temporary security-group rules when finished.
