# Automated patching with Systems Manager: separate policy, targeting, scheduling, and evidence

## Goal

Build a repeatable patch-management workflow for an Amazon Linux 2023 EC2 instance without SSH:

- use an EC2 instance role for SSM Agent connectivity;
- define approved patches with a Patch Manager baseline;
- separate maintenance-window target selection from baseline selection;
- scan daily and install weekly with `AWS-RunPatchBaseline`;
- read compliance back from Systems Manager; and
- route non-compliance events through EventBridge to SNS.

The transferable pattern is **policy → target → schedule → execution → evidence → cleanup**. Creating a resource is not the acceptance test; reading its downstream state back is.

## Environment

- AWS CloudShell or AWS CLI v2
- Region selected explicitly by the operator, for example `us-east-1`
- Amazon Linux 2023 EC2 instance
- EC2 role with `AmazonSSMManagedInstanceCore`
- Systems Manager managed-node status `Online`
- Dedicated security group with no inbound SSH rule required
- Patch Manager, Maintenance Windows, EventBridge, SNS, and optional CloudWatch read-back

This lab was executed in a disposable sandbox. The public artifact contains placeholders only: no account IDs, instance IDs, ARNs, IP addresses, emails, credentials, or private keys.

## Architecture

```text
Human/admin identity in CloudShell
        |
        | send-command / describe / register
        v
Systems Manager control plane
        ^                         |
        | outbound agent channel  | compliance state change
        |                         v
EC2 + SSM Agent + instance role  EventBridge rule
                                      |
                                      v
                                  SNS topic
```

Two tags deliberately have different jobs:

```text
Environment=Production  -> maintenance-window target selection
PatchGroup=Production   -> patch-baseline selection
```

The human/admin identity starts control-plane operations. The EC2 instance role is the identity used by the SSM Agent. They are not interchangeable.

## Implementation

### 1. Establish the execution context

```bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:?set AWS_REGION first}"
export AWS_DEFAULT_REGION="$AWS_REGION"

aws --version
aws sts get-caller-identity --query 'Account' --output text >/dev/null
printf 'Authenticated in %s\n' "$AWS_REGION"
```

Do not put the identity output into a repository. IAM is global; EC2, SSM, EventBridge, SNS, and CloudWatch operations should receive the selected Region explicitly.

### 2. Create the EC2 role and instance profile

The role trust policy is in [`policies/ec2-trust-policy.json`](policies/ec2-trust-policy.json). Attach the AWS-managed policy and create an instance profile:

```bash
set -euo pipefail

ROLE_NAME="${ROLE_NAME:-SSM-PatchLab-EC2-Role}"
INSTANCE_PROFILE_NAME="$ROLE_NAME"

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://policies/ec2-trust-policy.json

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --role-name "$ROLE_NAME"
```

The instance profile is what attaches the role to EC2 at launch. The role itself is not “attached to an instance” from inside the host.

### 3. Launch and verify an Amazon Linux 2023 target

Launch one small, currently eligible instance using the instance profile. Use a dedicated security group with no inbound SSH rule; SSM requires the agent, the role, and outbound connectivity—not an interactive SSH port.

Apply these tags:

```text
Name=ssm-patch-lab-01
Environment=Production
PatchGroup=Production
```

Verify the instance and SSM registration:

```bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:?set AWS_REGION first}"
export INSTANCE_ID="${INSTANCE_ID:?set INSTANCE_ID}"

aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{State:State.Name,Tags:Tags}' \
  --output table

aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName,PlatformVersion:PlatformVersion,AgentVersion:AgentVersion}' \
  --output table
```

Required evidence is `State=running`, `PingStatus=Online`, and Amazon Linux version `2023`. A running instance without `Online` SSM status is not ready for Patch Manager.

### 4. Create and associate the custom baseline

The baseline used `AMAZON_LINUX_2023` because that was the actual node platform. Its approval rule selected `Security` or `Bugfix` classifications with `Critical` severity, approved after seven days, and marked the compliance level `CRITICAL`.

The important distinction is that the baseline defines patch policy; it does not select an instance and it does not install anything by itself.

```bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:?set AWS_REGION first}"
export PATCH_BASELINE_NAME="${PATCH_BASELINE_NAME:-custom-baseline-ssm-patch-lab}"
export PATCH_GROUP="${PATCH_GROUP:-Production}"

cat > /tmp/approval-rules.json <<'JSON'
{
  "PatchRules": [
    {
      "PatchFilterGroup": {
        "PatchFilters": [
          {"Key": "CLASSIFICATION", "Values": ["Security", "Bugfix"]},
          {"Key": "SEVERITY", "Values": ["Critical"]}
        ]
      },
      "ApproveAfterDays": 7,
      "ComplianceLevel": "CRITICAL"
    }
  ]
}
JSON

PATCH_BASELINE_ID="$(aws ssm create-patch-baseline \
  --region "$AWS_REGION" \
  --name "$PATCH_BASELINE_NAME" \
  --description "Amazon Linux 2023 patch baseline" \
  --operating-system AMAZON_LINUX_2023 \
  --approval-rules file:///tmp/approval-rules.json \
  --approved-patches-compliance-level CRITICAL \
  --query 'BaselineId' \
  --output text)"

aws ssm register-patch-baseline-for-patch-group \
  --region "$AWS_REGION" \
  --baseline-id "$PATCH_BASELINE_ID" \
  --patch-group "$PATCH_GROUP"

aws ssm describe-patch-groups \
  --region "$AWS_REGION" \
  --query "Mappings[?PatchGroup=='${PATCH_GROUP}'].[PatchGroup,BaselineIdentity.BaselineName,BaselineIdentity.OperatingSystem]" \
  --output table
```

On reruns, discover an existing baseline with `NAME_PREFIX` and exact JMESPath matching. The installed CLI rejected `NAME` as a baseline filter during the lab.

### 5. Create the weekly install window

Create a maintenance-window service role trusted by `ssm.amazonaws.com` using [`policies/maintenance-window-trust-policy.json`](policies/maintenance-window-trust-policy.json), then attach `AmazonSSMMaintenanceWindowRole`.

The weekly window was configured as:

```text
Schedule: cron(0 2 ? * SUN *) UTC
Duration: 4 hours
Cutoff: 1 hour
```

Register a target using `Key=tag:Environment,Values=Production`, then register `AWS-RunPatchBaseline` with:

```json
{"RunCommand":{"Parameters":{"Operation":["Install"]}}}
```

Use `--max-concurrency 1` and `--max-errors 1` for the single-target lab. Read back the task with `get-maintenance-window-task` and inspect the nested `TaskInvocationParameters.RunCommand.Parameters.Operation` value. A task registration response alone does not prove that `Install` was stored.

### 6. Create the daily scan window

A separate scan window keeps compliance reporting frequent without installing patches every day:

```text
Schedule: cron(0 1 * * ? *) UTC
Duration: 2 hours
Cutoff: 1 hour
Target: tag:Environment=Production
Operation: Scan
MaxConcurrency: 100%
MaxErrors: 1
```

Register the same `AWS-RunPatchBaseline` document with:

```json
{"RunCommand":{"Parameters":{"Operation":["Scan"]}}}
```

`Scan` reports missing approved patches. It does not install patches or deliberately reboot the node.

### 7. Validate immediately with a direct scan

Maintenance Windows are schedule-driven. The CLI version used for the lab did not provide the assumed start-window operation, so the scheduled configuration was verified separately and a direct SSM scan supplied immediate evidence:

```bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:?set AWS_REGION first}"
export INSTANCE_ID="${INSTANCE_ID:?set INSTANCE_ID}"
export PATCH_GROUP="${PATCH_GROUP:-Production}"

COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunPatchBaseline \
  --parameters 'Operation=Scan' \
  --comment "Patch Manager compliance validation" \
  --timeout-seconds 600 \
  --query 'Command.CommandId' \
  --output text)"

aws ssm wait command-executed \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID"

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query '{Status:Status,ResponseCode:ResponseCode,Error:StandardErrorContent}' \
  --output json

aws ssm describe-instance-patch-states-for-patch-group \
  --region "$AWS_REGION" \
  --patch-group "$PATCH_GROUP" \
  --query 'InstancePatchStates[].{Operation:Operation,Missing:MissingCount,Failed:FailedCount}' \
  --output table
```

The direct path validates SSM connectivity, baseline selection, the document, and compliance reporting. It does not prove that the maintenance-window scheduler invoked the task.

### 8. Route non-compliance events to SNS

The first CloudWatch alarm recipe watched `AWS/SSM-PatchCompliance / ComplianceByPatchGroup`. After a successful scan, the account emitted zero matching metrics, leaving the alarm `INSUFFICIENT_DATA`. That resource was not treated as working monitoring.

The verified replacement was:

```text
Systems Manager Compliance event
  → EventBridge rule
  → SNS topic
```

The rule filters:

```json
{
  "source": ["aws.ssm"],
  "detail-type": ["Configuration Compliance State Change"],
  "detail": {
    "resource-type": ["managed-instance"],
    "compliance-type": ["Patch"],
    "compliance-status": ["non_compliant"]
  }
}
```

The topic policy in [`policies/eventbridge-sns-topic-policy.json`](policies/eventbridge-sns-topic-policy.json) grants only `sns:Publish` to EventBridge and scopes the source rule ARN. Using `SNS:*` failed with an out-of-scope action error.

Verify with:

```bash
aws events describe-rule --region "$AWS_REGION" --name "$RULE_NAME"
aws events list-targets-by-rule --region "$AWS_REGION" --rule "$RULE_NAME"
aws sns get-topic-attributes --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN"
```

An SNS topic with zero confirmed subscriptions is a configured routing endpoint, not a delivered human notification.

## Verification

| Check | Expected | Observed in the lab |
|---|---|---|
| EC2 state | `running` | Passed before cleanup |
| SSM managed node | `Online` | Passed; Amazon Linux 2023 |
| Weekly task | `Operation=Install` | Passed by nested task read-back |
| Daily task | `Operation=Scan` | Passed by nested task read-back |
| Direct scan | `Success`, response code `0` | Passed |
| Patch compliance | Missing `0`, failed `0` | Passed |
| EventBridge | Enabled, one SNS target | Passed |
| CloudWatch metric recipe | Metric datapoints | Not emitted in the tested account/Region |
| Cleanup | Active resources absent | Cleanup was run; final marker was not included in the public artifact |

## Cost

Use a small disposable instance and delete it immediately after validation. IAM, EventBridge rules, and SNS topics are not a reason to leave the lab running. SNS delivery may incur normal notification charges depending on the endpoint; no subscription was configured in the observed run.

## Cleanup

Cleanup is part of the implementation. Delete in dependency order:

1. Remove the EventBridge target and rule.
2. Delete the CloudWatch alarm and SNS topic.
3. Deregister maintenance-window tasks and targets.
4. Delete the maintenance windows.
5. Deregister the patch group and delete the custom baseline.
6. Terminate the EC2 instance and wait for `terminated`.
7. Delete the dedicated security group.
8. Remove the role from the instance profile, delete the profile, detach policies, and delete both IAM roles.

Use [`scripts/cleanup.sh`](scripts/cleanup.sh) only after setting every required ID and reviewing ownership. The script deletes in that order and then performs independent read-back checks, ending with `CLEANUP_VERIFIED_NO_LAB_RESOURCES_REMAIN` only when active lab resources are absent. A terminated EC2 record can remain historically visible; the security group, roles, profile, baseline, windows, tasks, rule, alarm, topic, and targets must be absent.

## What this lab teaches

- Patch compliance is relative to a particular baseline; it is not a complete vulnerability assessment.
- `Scan` and `Install` are different control-plane operations with different risk.
- Target-selection tags and baseline-selection tags are separate relationships.
- The EC2 role and the human/admin identity are different callers.
- A successful create call is weaker evidence than a read-back of the relationship it created.
- Monitoring must be tested at the datapoint/event layer, not judged by the existence of an alarm resource.
- A cleanup routine is part of an operational lab's acceptance criteria.

## Source and scope

The exercise was adapted from the [CloudProjects Automated Patching with Systems Manager recipe](https://github.com/mzazon/cloud-projects/tree/main/aws/automated-patching-systems-manager). This repository is a sanitized engineering write-up, not a copy of the catalog solution. The tested implementation corrected catalog drift for Amazon Linux 2023, CLI command availability, patch-filter semantics, and compliance monitoring.
