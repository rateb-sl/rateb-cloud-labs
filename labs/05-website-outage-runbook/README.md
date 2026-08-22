# Website outage runbook: isolate the broken layer

## Goal

Investigate a customer report that a website is unavailable by reproducing the failure, isolating the broken layer, making the smallest safe change, and verifying from outside again.

This is a repeatable training runbook, not a claim of a production incident.

## Request path

```text
Client → Internet Gateway → Route Table → NACL → Security Group → EC2 → Apache
```

“Instance is Running” proves only that the machine exists. Every hop in the request path must be tested separately.

## Implementation

### 1. Reproduce from outside

```bash
curl -v --max-time 15 http://<public-ip>
```

| Result | Meaning | Next layer |
|---|---|---|
| Timeout | Packets are being dropped | Route, NACL, or security group |
| Connection refused | Path is open but no service accepts the port | Apache/listener |
| HTTP 200 | Web path works | DNS or load balancer scope |

Timeout and refusal are different evidence. Do not troubleshoot them as the same failure.

### 2. Separate port reachability

```bash
ssh -i <your-key.pem> ec2-user@<public-ip>
```

If SSH works but HTTP times out, the instance path is open and the investigation should focus on TCP/80. If SSH also fails, inspect route, gateway, address, and NACL state.

For a public web server, the security group needs HTTP/TCP/80 from the intended source. SSH should remain restricted to the operator's address rather than opened broadly.

### 3. Check the host service

```bash
sudo systemctl status httpd
sudo ss -tlnp
```

If the service is stopped:

```bash
sudo systemctl start httpd
sudo systemctl enable httpd
```

A local listener proves host service state, not external reachability.

### 4. Check routing only when the path is isolated

Confirm:

- `0.0.0.0/0` targets an Internet Gateway for a public subnet.
- The gateway is attached to the VPC.
- The instance has a public IPv4 or Elastic IP.
- A custom NACL permits inbound HTTP and outbound ephemeral response ports.

### 5. Verify externally after the fix

```bash
curl -v --max-time 15 http://<public-ip>
```

The incident is not resolved until the external request succeeds and returns the expected page.

## Evidence boundaries

- `systemctl` proves service state on the host.
- SSH proves the path to port 22, not port 80.
- A security-group rule does not prove Apache is listening.
- Only a successful external request proves the website path works end to end.

## Cleanup

Remove temporary security-group rules and terminate the disposable instance after the runbook. Confirm the intended resources and rules are absent.
