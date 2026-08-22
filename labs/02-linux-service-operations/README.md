# Linux service operations: package, start, enable, verify

## Goal

Demonstrate the difference between installing a package, starting its service now, and enabling it for the next boot. Apache on Amazon Linux makes the three states visible.

## Environment

- Amazon Linux 2023 or another `systemd`-based Linux host
- `systemctl`
- `curl`

Amazon Linux uses the service name `httpd`; Ubuntu commonly uses `apache2`. Check `/etc/os-release` before reusing commands across distributions.

## Operating model

```text
package installed
  ≠ service running now
  ≠ service enabled for the next boot
  ≠ service reachable from the network
```

These are separate state layers. A reliable check tests each layer rather than treating one success message as proof of the whole path.

## Implementation

### 1. Install the package

```bash
sudo dnf install -y httpd
```

This changes package state only. It does not guarantee the service is running or listening.

### 2. Start and enable the service

```bash
sudo systemctl start httpd
sudo systemctl enable httpd
```

`start` changes runtime state. `enable` changes boot-time configuration. One does not imply the other.

### 3. Use the repository health check

[`scripts/check-service.sh`](scripts/check-service.sh) checks whether the service is active and enabled and can test a local HTTP endpoint.

```bash
chmod u+x scripts/check-service.sh
./scripts/check-service.sh httpd http://localhost
```

### 4. Verify each layer directly

```bash
systemctl is-active httpd
systemctl is-enabled httpd
curl -I http://localhost
```

Expected evidence:

- `active`: the process is running now.
- `enabled`: systemd will start it after reboot.
- HTTP response: the local service answered a request.

A local response does not prove internet reachability. An EC2 path also needs a public address, route, security group, and healthy host.

## Failure boundaries

```bash
sudo systemctl status httpd --no-pager
sudo journalctl -u httpd -n 80 --no-pager
sudo ss -ltnp
```

- Package installed but service stopped: runtime layer.
- Service active but no listener: process/configuration layer.
- Local response works but external request fails: network path or security-group layer.
- Do not use `kill -9` or `chmod 777` as the first response; inspect status, logs, ownership, and permissions.

## Cleanup

- Keep inbound access limited to the intended test source.
- Stop and disable the service when finished:

```bash
sudo systemctl disable --now httpd
```

- Terminate disposable EC2 instances after the lab.
