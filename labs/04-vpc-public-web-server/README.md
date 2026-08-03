# VPC and public web server

## Goal

Build a small VPC from scratch and prove one complete HTTP path end to end: a browser on the public internet reaching an Apache page served by an EC2 instance in a public subnet.

The point of this lab is not the drawing. It is the chain of separate requirements that all have to be true before a browser gets a page:

```text
Browser
  -> Internet Gateway attached to the VPC
  -> route table with 0.0.0.0/0 pointing at the gateway
  -> subnet explicitly associated with that route table
  -> security group allowing TCP/80
  -> EC2 instance with a public IPv4 address
  -> Apache installed and running, with a page in its document root
```

A subnet is not public because you named it public. It is public because the route table it actually uses sends internet traffic to an Internet Gateway.

## Environment

- AWS account with permission to create VPC, subnet, route table, security group, and EC2 resources
- Region used in this write-up: `us-west-2` (any region works)
- Amazon Linux 2 AMI, `t3.micro`

## What I built

1. VPC `10.0.0.0/16` using the VPC wizard with one public subnet (`10.0.0.0/24`) and one private subnet (`10.0.1.0/24`), an Internet Gateway, public/private route tables, and a NAT Gateway in one Availability Zone.
2. A second public subnet (`10.0.2.0/24`) and a second private subnet (`10.0.3.0/24`) in another AZ, each explicitly associated with the intended route table. Explicit association matters: a new subnet uses the main route table until you assign it.
3. A security group named `Web Security Group` allowing inbound HTTP (TCP 80) from `0.0.0.0/0`.
4. One EC2 instance (`Web Server 1`) in the public subnet, public IPv4 enabled, with the web security group attached.
5. A user-data script that installs Apache and writes a simple page. See [`scripts/user-data-httpd.sh`](scripts/user-data-httpd.sh).

## User data

The script in this repo is a clean version of what I used. It installs Apache, writes a static page, and enables the service so it survives a reboot.

```bash
#!/bin/bash
yum install -y httpd
cat > /var/www/html/index.html <<'EOF'
<html><head><title>My VPC web server</title></head>
<body><h1>Hello from a public subnet</h1></body></html>
EOF
systemctl enable httpd
systemctl start httpd
```

Notes:

- On Amazon Linux 2023 the package manager is `dnf`; change `yum install` to `dnf install` and use `dnf` throughout.
- User-data scripts run at first boot and can take a few extra minutes after the instance health checks pass. Check `/var/log/cloud-init-output.log` on the instance when something is missing.

## Verification

1. Wait until the instance shows `2/2 checks passed`.
2. Copy the instance Public IPv4 DNS name.
3. Visit `http://<public-ipv4-dns>` in a browser, or test from your machine:

```bash
curl -I --max-time 15 http://<public-ipv4-dns>
```

Expected: `HTTP/1.1 200 OK` and the page body.

Evidence boundaries that matter:

- `2/2 checks passed` proves EC2 infrastructure health, not that Apache is reachable from the internet.
- `curl -I http://localhost` on the instance proves the service responds locally. It does not prove the public path works.
- A browser page is the strongest end-to-end evidence in this lab: addressing, routing, policy, and service all had to work together.

## Troubleshooting

| Symptom | First layer to check | Common cause |
|---|---|---|
| Browser times out | address / path / policy | Missing `0.0.0.0/0 -> igw` route, wrong subnet association, or security group without TCP/80 |
| Connection refused | service on the host | Apache not installed or not running |
| No public IPv4 | EC2 launch settings | Auto-assign public IP was not enabled |
| Error page instead of yours | user data / document root | User data failed; check `/var/log/cloud-init-output.log` |
| Page works locally only | public path | Public subnet association or security group misconfigured |

## Cleanup

The VPC wizard creates a NAT Gateway, which is a paid resource. Do not leave it running in a normal account.

1. Terminate the EC2 instance.
2. Delete the NAT Gateway (release its Elastic IP if one was allocated).
3. Delete the VPC. AWS deletes the subnets, route tables, security groups, and Internet Gateway with it when nothing depends on them.

## What this lab teaches

- Routing and naming are separate facts. A subnet's name changes nothing; its route-table association changes everything.
- A security group permits a flow. It does not start services, assign addresses, or create routes.
- The fastest debugging path is to test one layer at a time and let the failure choose the next branch.
