#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:?set AWS_REGION}"
INSTANCE_ID="${INSTANCE_ID:?set INSTANCE_ID}"
PATCH_GROUP="${PATCH_GROUP:-Production}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

PING_STATUS="$(aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text)"
[[ "$PING_STATUS" == "Online" ]]

COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunPatchBaseline \
  --parameters 'Operation=Scan' \
  --comment "Patch Manager compliance validation" \
  --timeout-seconds 600 \
  --query 'Command.CommandId' \
  --output text)"
: "${COMMAND_ID:?send-command returned no CommandId}"

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
  --query 'InstancePatchStates[].{InstanceId:InstanceId,Operation:Operation,Missing:MissingCount,Failed:FailedCount}' \
  --output table
