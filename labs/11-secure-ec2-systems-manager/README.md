# Secure EC2 management with Systems Manager: manage without SSH

## Goal

Build a secure EC2 management path that avoids inbound SSH, long-lived keys, and bastion hosts.

The central design is a two-sided IAM model:

- the EC2 instance role lets the SSM Agent register and receive work;
- the human/operator identity starts Session Manager sessions and sends Run Command requests.

An instance can be online in Systems Manager while the operator still lacks `ssm:StartSession` or `ssm:SendCommand`.

## Environment

- AWS CLI v2 on macOS or AWS CloudShell
- Session Manager Plugin when using a local `aws ssm start-session`
- Amazon Linux 2023 x86_64 AMI
- Free Tier-eligible instance type discovered for the current account and Region
- Disposable VPC/subnet
- EC2 role with `AmazonSSMManagedInstanceCore`

## Architecture

```text
Human/admin CLI identity
  → ssm:StartSession / ssm:SendCommand
  → Systems Manager control plane
  ← outbound agent connection
EC2 instance + SSM Agent + instance role
  → no inbound SSH rule required
  → optional CloudWatch session logging
```

The human caller and instance role are deliberately separate. Mixing them creates confusing authorization failures.

## Implementation

### 1. Discover the target context and compatible AMI

```bash
set -euo pipefail
export AWS_REGION="${AWS_REGION:?set AWS_REGION first}"
export AWS_DEFAULT_REGION="$AWS_REGION"

aws sts get-caller-identity
aws ec2 describe-instance-types \
  --region "$AWS_REGION" \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].InstanceType' \
  --output text

AMI_ID="$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64' \
  --query Parameter.Value --output text)"
: "${AMI_ID:?AMI discovery returned no value}"
```

This prevents an empty Region, incompatible architecture, or non-eligible instance type from becoming a later launch failure.

### 2. Attach the instance role

Create an EC2-trusted role and attach:

```text
arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

The policy belongs to the instance role. The human caller needs separate permission to start sessions and send commands.

### 3. Launch without inbound SSH

Use a security group with no inbound port 22 rule and the outbound path required by the SSM Agent. Keep AMI architecture and instance type compatible.

### 4. Verify registration

```bash
aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[].{Instance:InstanceId,Ping:PingStatus,Agent:AgentVersion}' \
  --output table
```

`PingStatus=Online` proves agent registration and control-plane reachability. It does not prove the human caller can start a session.

### 5. Start a session from the human caller

```bash
aws sts get-caller-identity
aws ssm start-session --target "$INSTANCE_ID" --region "$AWS_REGION"
```

Run this from the Mac terminal or CloudShell, not from the EC2 instance role shell. Leave the session with `exit`.

### 6. Execute Run Command and read the result back

```bash
CMD_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name AWS-RunShellScript \
  --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
  --parameters 'commands=["hostname","uname -a","df -h"]' \
  --query 'Command.CommandId' --output text)"
: "${CMD_ID:?SendCommand returned no CommandId}"

aws ssm wait command-executed \
  --region "$AWS_REGION" \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID"

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json
```

The non-empty `CommandId` is a dependency check. If `send-command` fails, do not run the downstream invocation lookup with an empty ID.

### 7. Configure session logging

Validate the Session Manager preferences JSON locally before applying it, then read the stored document back. Heredoc terminators must start at column 1.

## Verification

The complete evidence chain is:

- intended human caller confirmed
- instance reports `PingStatus=Online`
- Session Manager opens without port 22 or an SSH key
- Run Command returns a non-empty ID and reaches `Success`
- command output is read back
- session logging points to the intended log group

## Failure boundaries

- Empty Region creates malformed SSM endpoints.
- Free Tier rejection is an account/instance-type issue, not an IAM issue.
- `ssm:StartSession` denied under an EC2 role usually means the wrong caller is being used.
- Duplicate security groups require idempotent discovery rather than a second create.
- A valid JSON document is not proof that the SSM document has the intended operational effect.

## Cleanup

Terminate the instance promptly. Remove the security group, instance profile, role attachment, role, and CloudWatch log group in dependency order. Verify all named resources are absent. Do not delete shared Session Manager preferences without confirming ownership.
