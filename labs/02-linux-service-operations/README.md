# Linux service operations: inspect, start, enable, verify

## Goal

Practice the operational difference between installing a package, starting its service now, and enabling it for the next boot. I used Apache on Amazon Linux as the example because it makes the difference visible quickly.

## Environment

- Amazon Linux 2023 or another `systemd`-based Linux host
- `systemctl`
- `curl` for a local HTTP check

On Amazon Linux, Apache is called `httpd`. On Ubuntu, the common service name is `apache2`. I check `/etc/os-release` before reusing package or service commands from another distribution.

## What I built

[`scripts/check-service.sh`](scripts/check-service.sh) is a small read-only health-check helper. It checks whether a named systemd service is active and enabled. If `curl` is available and the target is an HTTP service, it can also request a local endpoint.

```bash
chmod u+x scripts/check-service.sh
./scripts/check-service.sh httpd http://localhost
```

For an Amazon Linux test instance, the setup sequence is:

```bash
sudo dnf install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd
./scripts/check-service.sh httpd http://localhost
```

## Verification

```bash
systemctl is-active httpd
systemctl is-enabled httpd
curl -I http://localhost
```

The expected state is:

- `active`: Apache is running now.
- `enabled`: systemd is configured to start it after a reboot.
- a local HTTP response: the process is serving a request on the host.

These checks do not prove that the site is reachable from the internet. For EC2, that also depends on the instance state, route, network ACLs when relevant, and the security group allowing the intended inbound TCP port.

## Troubleshooting notes

```bash
sudo systemctl status httpd --no-pager
sudo journalctl -u httpd -n 80 --no-pager
sudo ss -ltnp
```

- `start` changes runtime state. `enable` changes boot-time configuration. One does not imply the other.
- A package can be installed while its service is stopped.
- Do not use `kill -9` as a first response to a service problem. Inspect the unit status and logs first.
- Avoid `chmod 777` when a service cannot read a file. Check the exact owner, group, mode bits, and parent-directory permissions.

## What I learned

```text
package installed ≠ service running ≠ service enabled
```

This looks small, but it matters during provisioning and incident work. A web server that works until the next reboot is not a finished setup.

## Security and cleanup

- Keep inbound network access narrow. Do not open port 80 to the world unless that is the intended test.
- Stop and disable the service when the disposable lab is finished:

```bash
sudo systemctl disable --now httpd
```

- Terminate temporary EC2 instances after the lab to avoid cost.
