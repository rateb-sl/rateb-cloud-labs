#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:?set AWS_REGION}"
INSTANCE_ID="${INSTANCE_ID:?set INSTANCE_ID}"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:?set SECURITY_GROUP_ID}"
PATCH_BASELINE_ID="${PATCH_BASELINE_ID:?set PATCH_BASELINE_ID}"
WEEKLY_WINDOW_ID="${WEEKLY_WINDOW_ID:?set WEEKLY_WINDOW_ID}"
DAILY_WINDOW_ID="${DAILY_WINDOW_ID:?set DAILY_WINDOW_ID}"
WEEKLY_TARGET_ID="${WEEKLY_TARGET_ID:?set WEEKLY_TARGET_ID}"
DAILY_TARGET_ID="${DAILY_TARGET_ID:?set DAILY_TARGET_ID}"
WEEKLY_TASK_ID="${WEEKLY_TASK_ID:?set WEEKLY_TASK_ID}"
DAILY_TASK_ID="${DAILY_TASK_ID:?set DAILY_TASK_ID}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

RULE_NAME="${RULE_NAME:-ssm-patch-lab-compliance-alerts}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-ssm-patch-lab-notifications}"
SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):${SNS_TOPIC_NAME}"
EC2_ROLE_NAME="${EC2_ROLE_NAME:-SSM-PatchLab-EC2-Role}"
MAINTENANCE_ROLE_NAME="${MAINTENANCE_ROLE_NAME:-SSM-PatchLab-Maintenance-Role}"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-SSM-PatchLab-EC2-Role}"

aws events remove-targets --region "$AWS_REGION" --rule "$RULE_NAME" --ids PatchComplianceSnsTarget
aws events delete-rule --region "$AWS_REGION" --name "$RULE_NAME"
aws cloudwatch delete-alarms --region "$AWS_REGION" --alarm-names PatchComplianceAlarm-ssm-patch-lab
aws sns delete-topic --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN"

aws ssm deregister-task-from-maintenance-window --region "$AWS_REGION" --window-id "$WEEKLY_WINDOW_ID" --window-task-id "$WEEKLY_TASK_ID"
aws ssm deregister-task-from-maintenance-window --region "$AWS_REGION" --window-id "$DAILY_WINDOW_ID" --window-task-id "$DAILY_TASK_ID"
aws ssm deregister-target-from-maintenance-window --region "$AWS_REGION" --window-id "$WEEKLY_WINDOW_ID" --window-target-id "$WEEKLY_TARGET_ID"
aws ssm deregister-target-from-maintenance-window --region "$AWS_REGION" --window-id "$DAILY_WINDOW_ID" --window-target-id "$DAILY_TARGET_ID"
aws ssm delete-maintenance-window --region "$AWS_REGION" --window-id "$WEEKLY_WINDOW_ID"
aws ssm delete-maintenance-window --region "$AWS_REGION" --window-id "$DAILY_WINDOW_ID"

aws ssm deregister-patch-baseline-for-patch-group --region "$AWS_REGION" --patch-group Production --baseline-id "$PATCH_BASELINE_ID"
aws ssm delete-patch-baseline --region "$AWS_REGION" --baseline-id "$PATCH_BASELINE_ID"

aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-terminated --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"
aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$SECURITY_GROUP_ID"

aws iam detach-role-policy --role-name "$EC2_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam remove-role-from-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$EC2_ROLE_NAME"
aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"
aws iam delete-role --role-name "$EC2_ROLE_NAME"
aws iam detach-role-policy --role-name "$MAINTENANCE_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole
aws iam delete-role --role-name "$MAINTENANCE_ROLE_NAME"

INSTANCE_STATE="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[].Instances[].State.Name' \
  --output text 2>/dev/null || true)"
if [[ -n "$INSTANCE_STATE" && "$INSTANCE_STATE" != "None" && "$INSTANCE_STATE" != "terminated" ]]; then
  printf 'ERROR: instance still active: %s\n' "$INSTANCE_STATE" >&2
  exit 1
fi

REMAINING_BASELINE="$(aws ssm describe-patch-baselines \
  --region "$AWS_REGION" \
  --filters Key=NAME_PREFIX,Values=custom-baseline-ssm-patch-lab \
  --query "BaselineIdentities[?BaselineName=='custom-baseline-ssm-patch-lab'].BaselineId" \
  --output text)"
[[ -z "$REMAINING_BASELINE" || "$REMAINING_BASELINE" == "None" ]]

REMAINING_WINDOWS="$(aws ssm describe-maintenance-windows \
  --region "$AWS_REGION" \
  --query "WindowIdentities[?Name=='ssm-patch-lab-weekly-window' || Name=='ssm-patch-lab-daily-scan-window'].WindowId" \
  --output text)"
[[ -z "$REMAINING_WINDOWS" || "$REMAINING_WINDOWS" == "None" ]]

REMAINING_RULE="$(aws events list-rules \
  --region "$AWS_REGION" \
  --query "Rules[?Name=='$RULE_NAME'].Name" \
  --output text)"
[[ -z "$REMAINING_RULE" || "$REMAINING_RULE" == "None" ]]

REMAINING_ALARM="$(aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names PatchComplianceAlarm-ssm-patch-lab \
  --query 'MetricAlarms[].AlarmName' \
  --output text)"
[[ -z "$REMAINING_ALARM" || "$REMAINING_ALARM" == "None" ]]

REMAINING_TOPIC="$(aws sns list-topics \
  --region "$AWS_REGION" \
  --query "Topics[?TopicArn=='$SNS_TOPIC_ARN'].TopicArn" \
  --output text)"
[[ -z "$REMAINING_TOPIC" || "$REMAINING_TOPIC" == "None" ]]

REMAINING_SG="$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --group-ids "$SECURITY_GROUP_ID" \
  --query 'SecurityGroups[].GroupId' \
  --output text 2>/dev/null || true)"
[[ -z "$REMAINING_SG" || "$REMAINING_SG" == "None" ]]

REMAINING_PROFILE="$(aws iam list-instance-profiles \
  --query "InstanceProfiles[?InstanceProfileName=='$INSTANCE_PROFILE_NAME'].InstanceProfileName" \
  --output text)"
[[ -z "$REMAINING_PROFILE" || "$REMAINING_PROFILE" == "None" ]]

REMAINING_ROLES="$(aws iam list-roles \
  --query "Roles[?RoleName=='$EC2_ROLE_NAME' || RoleName=='$MAINTENANCE_ROLE_NAME'].RoleName" \
  --output text)"
[[ -z "$REMAINING_ROLES" || "$REMAINING_ROLES" == "None" ]]

printf 'CLEANUP_VERIFIED_NO_LAB_RESOURCES_REMAIN\n'
