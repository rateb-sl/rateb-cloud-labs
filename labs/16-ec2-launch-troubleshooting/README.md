# EC2 launch troubleshooting: make the request scope consistent

## Goal

Diagnose an EC2 launch that fails because the request uses an AMI in the wrong Region, then separate network reachability, guest-service state, first-boot configuration, and application behavior into independent evidence gates.

The transferable pattern is simple: follow the value from discovery to the API request, then test the system from the outside in. A successful EC2 launch is not the same thing as a working website.

## Environment

- Temporary AWS training account
- Amazon Linux EC2 hosts
- AWS CLI from a pre-provisioned CLI host
- EC2 Instance Connect for host access
- Apache, MariaDB, and PHP deployed by EC2 user data
- `nmap` used from the CLI host for TCP reachability

All account-specific identifiers, credentials, public addresses, and course-provided source material are intentionally excluded.

## Architecture and request path

```text
AWS CLI on CLI host
  → discover Cafe VPC, subnet, key pair, and AMI in one Region
  → EC2 RunInstances
  → public IPv4 address
  → security-group TCP/80 path
  → Apache/httpd on the instance
  → cloud-init user data
  → PHP application and MariaDB
```

The Region is part of the request context. AMI IDs and regional networking resources must be interpreted in the same Region as the launch request.

## Failure and repair

The first run reached security-group creation but `RunInstances` returned `InvalidAMIID.NotFound`. The script discovered the VPC and AMI using a shell variable named `$region`, but the launch command used a hard-coded Region value.

The smallest repair was to preserve the existing discovery logic and change the launch argument from a literal Region to the discovered value:

```bash
# Incorrect
--region us-east-1

# Correct for this script's discovery flow
--region $region
```

Before rerunning a script that creates cloud resources, keep its backup and follow its lab-scoped cleanup prompt. Do not replace the AMI with a guessed ID from another Region.

A syntax check confirms only that Bash can parse the file:

```bash
bash -n create-lamp-instance-v2.sh
```

It does not prove that AWS will accept the request. The useful runtime evidence is the actual `RunInstances` response and the later public-address lookup.

## Layered verification

### 1. AWS-side launch evidence

Use the CLI host to confirm the target instance is running and has a public address. Filter by the temporary lab tag or inspect the exact instance selected in the console; do not rely on a success message printed by a wrapper script.

```bash
aws ec2 describe-instances \
  --region "$LAB_REGION" \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],State:State.Name,PublicIP:PublicIpAddress,Type:InstanceType}' \
  --output table
```

The launch is accepted when the intended application instance is running and has a public IPv4 address. This does not prove that user data completed or that HTTP works.

### 2. Network reachability

From the CLI host, scan only the port required for the web test:

```bash
PUBLIC_IP='<temporary-public-ip>'
nmap -Pn -p 80 "$PUBLIC_IP"
```

`80/tcp open` proves that the public path reaches a listener. `closed` or `filtered` requires separating security-group, routing, and guest-service causes. Do not treat a browser timeout as proof of which layer is broken.

### 3. Guest service state

Connect to the application instance with the required access method, then verify the host identity before inspecting services:

```bash
printf 'user=%s\nhost=%s\npwd=%s\n' "$(whoami)" "$(hostname)" "$(pwd)"
sudo systemctl is-active httpd
```

Expected evidence is the remote web-server identity and `active`. This proves the Apache process state inside the guest; it does not prove the external browser path.

### 4. First-boot evidence

Read the end of the cloud-init output after user data has had time to finish:

```bash
sudo tail -n 120 /var/log/cloud-init-output.log
```

Strong evidence includes the application archive being downloaded and extracted, database setup completing, and a cloud-init completion message. Package installation alone is only partial evidence.

### 5. Application and persistence evidence

The intended application check is:

```text
http://<public-ip>/cafe
```

The menu route is:

```text
http://<public-ip>/cafe/menu.php
```

A complete application test requires the Café page to load, two different orders to be submitted, and both orders to appear in Order History. That exercises the HTTP route, PHP application logic, and database persistence together.

## Observed results

| Layer | Observed result | Boundary |
| --- | --- | --- |
| AWS CLI configuration | Lab Region and JSON output configured; identity check succeeded | Authentication was verified, not broad authorization |
| EC2 request | Initial AMI error caused by a hard-coded launch Region; corrected to `$region` | The repair was specific to the script's Region value flow |
| Instance launch | The target instance was created and received a public address | Does not prove first-boot completion |
| TCP reachability | `80/tcp` reported open by `nmap` | Does not prove the expected application response |
| Apache | `httpd` reported active on the web server | Does not prove PHP/database behavior |
| Bootstrap | Café files were extracted, database creation completed, and cloud-init finished | Does not replace an end-to-end application test |
| Café route | The sandbox browser timed out while requesting `/cafe` even though port 80 and Apache checks passed | Application success and database-backed ordering remain unverified in this run |

The timeout is recorded as an evidence boundary, not silently converted into an application success claim. A production investigation would continue by comparing the current public address, testing from an independent client, and checking the exact HTTP response path without relaunching unrelated resources.

## Cleanup

Managed training resources should be ended from the training platform after the required observations. In a standalone AWS account, terminate the temporary instance and remove its dedicated security group only after recording the identifiers needed for the cleanup check.

Verify cleanup from the same Region and account context. A terminated EC2 record may remain in the API for a while; the important evidence is that the instance is terminated and that temporary dependent resources no longer remain. Never claim cleanup from a wrapper script's final message alone.

## What this lab teaches

- Region is part of an AWS resource request, not just a console display setting.
- AMI IDs are Region-specific; discovery and `RunInstances` must agree.
- Security-group reachability and guest-service state are separate gates.
- Cloud-init output is stronger bootstrap evidence than a decorative success message.
- A running instance, open port, and active Apache process still do not prove application or database functionality.
- Troubleshooting is more reliable when each layer has one focused test and one explicit evidence boundary.
