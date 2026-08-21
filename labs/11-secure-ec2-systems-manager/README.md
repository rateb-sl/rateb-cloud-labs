# Secure EC2 management with Systems Manager: manage without SSH

## Goal

Build a secure EC2 management path that avoids inbound SSH, long-lived keys, and bastion hosts.

The transferable pattern is a two-sided IAM design:

- the **EC2 instance role** lets the SSM Agent register and receive work;
- the **human/operator identity** starts Session Manager sessions and sends Run Command requests.

That separation matters. An instance can be online in Systems Manager while the person starting a session still lacks `ssm:StartSession` or `ssm:SendCommand`.

## Environment

- AWS CLI v2 on macOS or AWS CloudShell
- AWS Systems Manager Session Manager Plugin on the client when using `aws ssm start-session`
- Amazon Linux 2023 x86_64 AMI
- A Free Tier-eligible instance type discovered for the current account and region; this run used `t3.micro`
- One default VPC and subnet for disposable practice
- The EC2 role uses `AmazonSSMManagedInstanceCore`
- Set `AWS_REGION` explicitly; replace every placeholder before running commands

This write-up contains no real account IDs, instance IDs, IP addresses, credentials, or private course material.

## Architecture

```text
Human/admin CLI identity
        |
        | ssm:StartSession / ssm:SendCommand
        v
Systems Manager control plane
        ^
        | outbound agent connection
        |
EC2 instance + SSM Agent + AmazonSSMManagedInstanceCore
        |
        +-- no inbound SSH rule required
        +-- optional CloudWatch Logs session logging
```

## Key implementation steps

### 1. Discover the environment before creating resources

```bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:?set AWS_REGION first}"
export AWS_DEFAULT_REGION="$AWS_REGION"

aws sts get-caller-identity
aws configure get region

aws ec2 describe-instance-types \
  --region "$AWS_REGION" \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].InstanceType' \
  --output text

AMI_ID=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64' \
  --query 'Parameter.Value' \
  --output text)

: "${AMI_ID:?AMI discovery returned an empty value}"
```

An endpoint such as `https://ssm..amazonaws.com` means the region is empty. Fix the shell/profile configuration before continuing; do not guess an endpoint or AMI ID.

### 2. Attach the instance role

Create an EC2-trusted IAM role and attach:

```text
arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

Attach the role to an instance profile, then attach the profile at launch. The policy belongs to the **role**, not directly to the EC2 instance.

### 3. Launch without inbound SSH

Use a security group with no inbound SSH rule and allow the normal outbound path required by the SSM Agent. Keep the instance type and AMI architecture compatible: an x86_64 AMI pairs with `t3.micro`; ARM families such as `t4g.micro` require an ARM64 AMI.

### 4. Verify Systems Manager registration

```bash
aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[].{Instance:InstanceId,Ping:PingStatus,Agent:AgentVersion}' \
  --output table
```

Expected evidence is `PingStatus=Online`. That proves registration and reachability to Systems Manager; it does not prove that the human caller is authorized to start a session.

### 5. Start Session Manager from the human/admin machine

Run this from Mac Terminal or CloudShell—not from the EC2 shell prompt:

```bash
aws sts get-caller-identity

aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region "$AWS_REGION"
```

The client needs the Session Manager Plugin when running from a local Mac. CloudShell normally includes it. Leave the session with `exit`.

### 6. Use Run Command from the human/admin machine

```bash
CMD_ID=$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name 'AWS-RunShellScript' \
  --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
  --parameters 'commands=["hostname","uname -a","df -h"]' \
  --query 'Command.CommandId' \
  --output text)

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

If `send-command` fails, do not run `get-command-invocation` with an empty command ID. Fix the first error first.

### 7. Configure and verify session logging

Create or update the `SSM-SessionManagerRunShell` Session document with a CloudWatch log group. Validate the local JSON before sending it to AWS:

```bash
python3 -m json.tool SessionManagerRunShell.json

aws ssm get-document \
  --region "$AWS_REGION" \
  --name 'SSM-SessionManagerRunShell' \
  --query Content \
  --output text
```

Heredoc terminators must start at column 1:

```bash
cat > SessionManagerRunShell.json << EOF
{}
EOF
```

## Troubleshooting map

| Symptom | Layer | First safe check | Meaning |
|---|---|---|---|
| `https://ssm..amazonaws.com` | Shell/region | `printf '%s\n' "$AWS_REGION"` | Region is empty. |
| `--image-id: expected one argument` | Variable/discovery | Print `AMI_ID` and rerun the regional lookup | AMI discovery failed or the variable was unset. |
| Free Tier rejection | Account/instance type | `describe-instance-types --filters Name=free-tier-eligible,Values=true` | The requested type is not eligible for this account/offer. |
| `ssm:StartSession` denied under an EC2 role | Caller identity | `aws sts get-caller-identity` | You are using the instance role instead of the human/admin identity. |
| `ssm:SendCommand` denied | Caller authorization | Check the caller ARN and policy | The instance role's agent policy is not the operator's policy. |
| `--command-id: expected one argument` | Dependency failure | Inspect the preceding `send-command` error | No command ID was returned. |
| `heredoc>` prompt | Shell syntax | Finish with column-1 `EOF`, or cancel and rerun | The shell is still reading the file body. |
| `InvalidDocumentContent` | JSON | `python3 -m json.tool file.json` | The payload is malformed before AWS can use it. |
| Duplicate security group | Rerun/idempotency | `describe-security-groups` by name and VPC | A previous attempt created part of the lab; reuse or clean it deliberately. |

## Verification checklist

- [ ] `aws sts get-caller-identity` shows the intended human/admin caller before Session Manager/Run Command.
- [ ] The instance reports `PingStatus=Online`.
- [ ] Session Manager opens without port 22 or an SSH key.
- [ ] Run Command returns a non-empty `CommandId` and reaches `Success`.
- [ ] Command output is read back with `get-command-invocation`.
- [ ] Session Manager preferences contain the intended CloudWatch log group.
- [ ] Cleanup verification shows no lab EC2 instance, security group, instance profile, IAM role, or log group remaining.

## Cost

Use the smallest Free Tier-eligible instance type for the current account and region. Stop/terminate disposable compute promptly. EBS volumes, public IPv4 addresses, data transfer, CloudWatch Logs, and other services can have separate pricing or quota rules. Check the live AWS Free Tier page before launching.

## Cleanup

Delete the lab resources in dependency order:

1. Terminate the EC2 instance and wait for `terminated`.
2. Delete the lab security group.
3. Remove the role from its instance profile.
4. Delete the instance profile.
5. Detach the SSM managed policy.
6. Delete the IAM role.
7. Delete the lab CloudWatch log group.
8. Re-run `describe`/`get`/`list` checks and confirm the named resources are absent.

Do not delete a shared Session Manager preferences document unless it was created solely for the disposable lab and its ownership is confirmed.

## What this lab teaches

- Secure management is a control-plane pattern, not an open SSH-port pattern.
- IAM has separate identities and permission surfaces: operator, instance role, and SSM document.
- Good automation fails at the first bad dependency instead of producing misleading downstream errors.
- Reliable lab work is inspect → decide → implement → verify → clean up.
