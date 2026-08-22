# VPC public web server: prove the complete HTTP path

## Goal

Build a small VPC and prove one complete path from an external client to an Apache page on an EC2 instance in a public subnet.

## Environment

- AWS account with VPC, EC2, and networking permissions
- Region selected explicitly
- Amazon Linux 2 or Amazon Linux 2023 with a compatible package command
- Disposable VPC, subnets, route tables, security group, NAT gateway, and EC2 instance

## Architecture

```text
External client
  → public IPv4/DNS
  → subnet route table: 0.0.0.0/0 → Internet Gateway
  → VPC Internet Gateway
  → security group: TCP/80 allowed
  → EC2 instance
  → Apache listener and document root
```

A subnet is public because of its effective route table, not because of its name. A security group controls a flow; it does not create a route, assign an address, or start Apache.

## Implementation

### 1. Define address and subnet state

The implementation used a `10.0.0.0/16` VPC with public and private subnets across two Availability Zones. Each subnet was explicitly associated with its intended route table.

The important decision is to inspect the effective association. A newly created subnet can use the main route table until an explicit association is made.

### 2. Establish internet routing

The public route table needs:

```text
0.0.0.0/0 → Internet Gateway attached to this VPC
```

Private subnets use private routing. A NAT Gateway may provide outbound access for private resources, but it is not an inbound path and is chargeable.

### 3. Allow only the application flow

The web security group permits TCP/80 from the intended test source. The EC2 instance is launched in the public subnet with public IPv4 enabled and the web security group attached.

### 4. Provision the service

[`scripts/user-data-httpd.sh`](scripts/user-data-httpd.sh) installs Apache, writes the page, and enables the service. On Amazon Linux 2023, use `dnf`; on Amazon Linux 2, use `yum`.

```bash
#!/bin/bash
set -euo pipefail

dnf install -y httpd
printf '%s\n' 'Hello from a public subnet' > /var/www/html/index.html
systemctl enable --now httpd
```

### 5. Verify from outside

Wait for EC2 status checks, then test the public DNS name:

```bash
curl -I --max-time 15 http://<public-ipv4-dns>
```

`2/2 checks passed` proves EC2 infrastructure health. `curl localhost` proves the service responds locally. Only the external request proves the complete public path.

## Troubleshooting by layer

| Symptom | First layer | Typical cause |
|---|---|---|
| Timeout | Address, route, or policy | Missing IGW route, wrong association, or no TCP/80 rule |
| Connection refused | Host service | Apache is not installed, running, or listening |
| No public IPv4 | Launch state | Auto-assign public IP was disabled |
| Default/error page | Provisioning | User data failed or wrote the wrong document root |
| Local works, public fails | Network path | Route table, gateway, address, or security group |

## Cleanup

NAT Gateway is chargeable. Cleanup order:

1. Terminate EC2.
2. Delete the NAT Gateway and release its Elastic IP.
3. Delete the VPC and confirm dependent networking resources are gone.

Read the VPC, EC2, NAT, and gateway state back after deletion.
