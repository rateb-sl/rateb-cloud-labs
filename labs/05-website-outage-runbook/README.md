# Website outage runbook

## Goal

A structured way to investigate a customer report that a website is unavailable. The method is outside-in: reproduce the failure, identify which layer stopped the request, fix the smallest thing, and verify from outside again.

This runbook is a guided training scenario (ticket: customer website unavailable since morning, instance shows Running, browser times out). It is written as a repeatable procedure, not as a record of a production incident.

## The mental model

```text
Browser -> Internet Gateway -> Route Table -> NACL -> Security Group -> EC2 (Apache)
```

"Instance is Running" only proves the machine exists. The fault lives somewhere on this path. Isolate which hop breaks by testing from the outside in.

## Investigation steps

### Step 1. Reproduce from your machine

```bash
curl -v --max-time 15 http://<PUBLIC_IP>
```

| Result | Meaning | Next step |
|---|---|---|
| `(28) Operation timed out` | Packets dropped, likely a routing or policy layer | Step 2 |
| `(7) Connection refused` | Packets arrive, nothing listening on port 80 | Step 3 |
| `HTTP 200` | Site works from the internet; problem is DNS or the load balancer | Stop |

A timeout and a connection refused are different evidence. A timeout means something is silently dropping the traffic. A refusal means the network path is open and the service is closed.

### Step 2. Can you reach the instance at all?

```bash
ssh -i <your-key.pem> ec2-user@<PUBLIC_IP>
```

- SSH works: the network path is open; the break is specific to port 80. Check the security group, then Apache.
- SSH also times out: the instance is isolated. Check the route table, Internet Gateway, and network ACL.

Security group check (AWS Console):

- EC2 -> Instances -> your instance -> Security tab.
- Required inbound rules:

```text
Type: HTTP (TCP 80)   Source: 0.0.0.0/0   missing = the bug
Type: SSH (TCP 22)    Source: your-ip/32
```

Fix: add the HTTP rule and save.

Network ACL check (only if SSH fails too):

- VPC -> Network ACLs. Default NACL allows all; a custom one may block.
- Inbound TCP 80 from `0.0.0.0/0` must be ALLOW.
- Outbound TCP 1024-65535 (ephemeral ports) must be ALLOW so replies can leave.

### Step 3. Is Apache alive?

```bash
sudo systemctl status httpd
```

- Not running:

```bash
sudo systemctl start httpd
sudo systemctl enable httpd   # survives reboot
```

- Running but the site is still down, check the listener:

```bash
sudo ss -tlnp | grep :80     # expect httpd on 0.0.0.0:80
```

- Nothing listening: install it. `sudo dnf install -y httpd` on Amazon Linux 2023, `sudo yum install -y httpd` on Amazon Linux 2.

### Step 4. Routing (only if SSH is dead too)

- Route table: does the main table have `0.0.0.0/0` pointing to an Internet Gateway, not a NAT?
- Internet Gateway: attached to the VPC?
- Public IP: the instance must have a public IPv4 or Elastic IP. Without one, nothing outside can reach it.

### Step 5. Verify from outside, do not skip

```bash
curl -v --max-time 15 http://<PUBLIC_IP>
```

Expected: `HTTP/1.1 200 OK` plus the site HTML. Then retry in a browser.

## Likely root cause for this ticket

Instance Running, SSH reachable, but the security group has no inbound rule for TCP 80. The security group drops the packets silently, which is why the browser times out instead of getting a refusal.

## Evidence rules

- `systemctl status httpd` proves service state on the host, not internet reachability.
- A successful SSH proves the path to port 22, not port 80.
- The only proof that the website is restored is a successful external request (curl or browser) after the fix.
