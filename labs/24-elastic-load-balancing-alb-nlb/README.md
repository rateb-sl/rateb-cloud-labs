# Elastic Load Balancing with ALB and NLB: route HTTP and TCP traffic safely

## Goal

Build and verify two public load-balancing paths to the same pair of EC2 web servers:

```text
Client
  ├── HTTP → Application Load Balancer → HTTP target group → EC2 instances
  └── TCP  → Network Load Balancer    → TCP target group  → EC2 instances
```

The transferable pattern is to separate the public entry points from the backend security boundary, register targets through target groups, verify health before testing traffic, and delete billable resources in dependency order.

## Environment

- AWS CLI v2 with an authenticated named profile
- One selected AWS Region
- A VPC with at least two subnets in different Availability Zones
- Amazon Linux 2023 `x86_64` AMI
- Two `t3.micro` EC2 instances for the disposable test
- No SSH exposure is required for this lab

The examples use placeholders only. They contain no credentials, account identifiers, instance IDs, public IP addresses, ARNs, or live DNS names.

## Architecture and security boundaries

The lab uses three security groups:

- **ALB security group:** permits public TCP/80 to the ALB.
- **NLB security group:** permits public TCP/80 to the NLB.
- **EC2 security group:** permits TCP/80 only from the ALB and NLB security groups.

The EC2 instances are not directly reachable from the public internet on port 80. The load balancer security groups are referenced as sources rather than replaced with backend IP ranges.

The ALB and NLB use the same two instances but different target groups. The ALB target group forwards HTTP. The NLB target group forwards TCP while using an HTTP `/` health check to verify the Apache service.

## Build outline

Persist non-secret values such as the Region, VPC ID, subnet IDs, and generated project name in a local variables file. Do not persist credentials or account-specific identifiers in Git.

### Create the security boundary

```bash
ALB_SG_ID="$(aws ec2 create-security-group \
  --group-name "${PROJECT_NAME}-alb-sg" \
  --description "ALB public HTTP traffic" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query GroupId --output text)"

NLB_SG_ID="$(aws ec2 create-security-group \
  --group-name "${PROJECT_NAME}-nlb-sg" \
  --description "NLB public TCP traffic" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query GroupId --output text)"

EC2_SG_ID="$(aws ec2 create-security-group \
  --group-name "${PROJECT_NAME}-ec2-sg" \
  --description "EC2 traffic only from load balancers" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query GroupId --output text)"
```

Allow public HTTP only at the two load-balancer boundaries. Add backend HTTP rules using `--source-group "$ALB_SG_ID"` and `--source-group "$NLB_SG_ID"`. Do not add a public SSH rule unless a separate lab explicitly requires it.

### Launch the backends

Launch one Amazon Linux 2023 instance in each selected Availability Zone with:

- The EC2 security group
- An explicit public IPv4 setting if the disposable lab requires package installation from the internet
- IMDSv2 required
- User data that installs Apache and renders the instance ID and Availability Zone in `/var/www/html/index.html`

Read back lifecycle state, Availability Zone, subnet, and EC2 status checks before registering the instances.

### Create and register target groups

```bash
ALB_TG_ARN="$(aws elbv2 create-target-group \
  --name "$ALB_TG_NAME" \
  --protocol HTTP --port 80 --target-type instance \
  --vpc-id "$VPC_ID" --region "$AWS_REGION" \
  --health-check-protocol HTTP --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"

NLB_TG_ARN="$(aws elbv2 create-target-group \
  --name "$NLB_TG_NAME" \
  --protocol TCP --port 80 --target-type instance \
  --vpc-id "$VPC_ID" --region "$AWS_REGION" \
  --health-check-protocol HTTP --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"

aws elbv2 register-targets \
  --target-group-arn "$ALB_TG_ARN" \
  --targets "Id=$INSTANCE_1_ID,Port=80" "Id=$INSTANCE_2_ID,Port=80" \
  --region "$AWS_REGION"

aws elbv2 register-targets \
  --target-group-arn "$NLB_TG_ARN" \
  --targets "Id=$INSTANCE_1_ID,Port=80" "Id=$INSTANCE_2_ID,Port=80" \
  --region "$AWS_REGION"
```

A target group can report `unused` until a listener uses it. That state does not mean the EC2 web server failed; read target health again after the corresponding listener exists.

### Create the load balancers and listeners

Create both load balancers across the two selected subnets. Attach the NLB security group during NLB creation; this is the safe current path for a Network Load Balancer that should have an inbound security boundary.

```bash
ALB_ARN="$(aws elbv2 create-load-balancer \
  --name "$ALB_NAME" --type application --scheme internet-facing \
  --ip-address-type ipv4 --subnets "$SUBNET_A_ID" "$SUBNET_B_ID" \
  --security-groups "$ALB_SG_ID" --region "$AWS_REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)"

NLB_ARN="$(aws elbv2 create-load-balancer \
  --name "$NLB_NAME" --type network --scheme internet-facing \
  --ip-address-type ipv4 --subnets "$SUBNET_A_ID" "$SUBNET_B_ID" \
  --security-groups "$NLB_SG_ID" --region "$AWS_REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
```

Create an HTTP/80 listener on the ALB and a TCP/80 listener on the NLB. Each listener forwards to its matching target group.

```bash
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$ALB_TG_ARN" \
  --region "$AWS_REGION"

aws elbv2 create-listener \
  --load-balancer-arn "$NLB_ARN" \
  --protocol TCP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$NLB_TG_ARN" \
  --region "$AWS_REGION"
```

## Target-group attributes

The verified configuration used:

| Target group | Attributes |
| --- | --- |
| ALB | Cookie stickiness enabled, `lb_cookie`, 86400-second cookie duration, 30-second deregistration delay |
| NLB | Client-IP preservation enabled, 30-second deregistration delay |

Always read attributes back after modifying them. A successful modification request is not enough; in the observed run, the first NLB read-back still showed the default 300-second delay and required a focused correction.

## Verification

### Control-plane state

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$ALB_TG_ARN" \
  --region "$AWS_REGION" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State}' \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn "$NLB_TG_ARN" \
  --region "$AWS_REGION" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State}' \
  --output table
```

Expected evidence is two `healthy` targets in each target group. Health status proves the load balancer can reach the configured target path; it does not prove that every future application request will succeed.

### External request path

Resolve each load balancer DNS name from its ARN instead of copying a stale value:

```bash
ALB_DNS="$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION" \
  --query 'LoadBalancers[0].DNSName' --output text)"

NLB_DNS="$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$NLB_ARN" --region "$AWS_REGION" \
  --query 'LoadBalancers[0].DNSName' --output text)"

curl -fsS --max-time 10 "http://${ALB_DNS}/"
curl -fsS --max-time 10 --write-out '\nHTTP status: %{http_code}\n' "http://${NLB_DNS}/"
```

Observed execution evidence:

- Five ALB requests returned the expected backend page and reached both backend instances and Availability Zones.
- Five NLB requests returned HTTP 200 and reached both backend instances and Availability Zones.
- Both ALB and NLB target groups reported healthy targets before endpoint testing.

A successful response proves the public request path at that moment. Multiple backend identities demonstrate that requests reached more than one target; they do not guarantee equal distribution.

## Cost

ALB, NLB, EC2 instances, and public IPv4 addresses can incur charges while they exist. Use the smallest disposable resources needed for the test and delete them promptly after verification. A clean resource inventory prevents ongoing resource-hour charges, but it does not erase usage already recorded in billing history.

## Cleanup

Delete in dependency order:

```text
listeners
→ load balancers
→ target groups
→ EC2 instances
→ security groups
→ local non-secret variables and bootstrap files
```

Verify each class with `describe-*` or `list-*` after deletion. Accept terminated EC2 records as normal historical state, but require no active instances. Confirm that project load balancers, target groups, active instances, and security groups are absent.

## What this lab teaches

- ALB is HTTP-aware Layer 7 routing; NLB is TCP-level Layer 4 routing.
- Target groups are the bridge between load balancers and compute targets.
- A target can be registered yet `unused` until a listener references the target group.
- Health checks are independent evidence from resource creation and external traffic tests.
- Security-group references express the intended load-balancer-to-backend relationship better than broad backend CIDR rules.
- NLB security-group association belongs in the creation decision.
- Read state back after every mutation, and treat cleanup as part of the lab rather than an optional final step.

## Source

- [CloudProjects: Elastic Load Balancing with ALB and NLB](https://github.com/mzazon/cloud-projects/tree/main/aws/elastic-load-balancing-alb-nlb)
- [AWS: Security groups for Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-update-security-groups.html)
- [AWS: Security groups for Network Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-security-groups.html)
- [AWS: Target groups for Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [AWS: Create a Network Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/create-network-load-balancer.html)
