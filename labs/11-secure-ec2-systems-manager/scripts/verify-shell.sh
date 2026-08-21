#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?set AWS_REGION}"
: "${INSTANCE_ID:?set INSTANCE_ID}"

export AWS_DEFAULT_REGION="$AWS_REGION"

aws sts get-caller-identity
aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[].{Instance:InstanceId,Ping:PingStatus,Agent:AgentVersion}' \
  --output table
