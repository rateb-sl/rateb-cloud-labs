#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$SCRIPT_DIR/.lab-state"
mkdir -p "$STATE_DIR"

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
: "${AWS_REGION:?Set AWS_REGION}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
export AWS_DEFAULT_REGION="$AWS_REGION"

LAB_SUFFIX="${LAB_SUFFIX:-$(date +%s)-$RANDOM}"
BUCKET_NAME="data-processing-${LAB_SUFFIX}"
PROCESSOR_NAME="data-processor-${LAB_SUFFIX}"
HANDLER_NAME="error-handler-${LAB_SUFFIX}"
DLQ_NAME="data-processing-dlq-${LAB_SUFFIX}"
TOPIC_NAME="data-processing-alerts-${LAB_SUFFIX}"
ROLE_NAME="data-processing-lambda-role-${LAB_SUFFIX}"

if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION"
fi
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

TOPIC_ARN="$(aws sns create-topic --name "$TOPIC_NAME" --query TopicArn --output text)"
QUEUE_URL="$(aws sqs create-queue --queue-name "$DLQ_NAME" --attributes VisibilityTimeout=300 --query QueueUrl --output text)"
QUEUE_ARN="$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)"

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$SCRIPT_DIR/policies/trust-policy.json"
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)"

POLICY_FILE="$STATE_DIR/execution-policy.json"
python3 - "$POLICY_FILE" "$BUCKET_NAME" "$QUEUE_ARN" "$TOPIC_ARN" <<'PY'
import json
import sys

path, bucket, queue_arn, topic_arn = sys.argv[1:]
policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ProcessBucketObjects",
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"],
            "Resource": [
                f"arn:aws:s3:::{bucket}/data/*",
                f"arn:aws:s3:::{bucket}/reports/*",
            ],
        },
        {
            "Sid": "WriteAndConsumeFailures",
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
                "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes",
            ],
            "Resource": queue_arn,
        },
        {
            "Sid": "PublishFailureAlert",
            "Effect": "Allow",
            "Action": "sns:Publish",
            "Resource": topic_arn,
        },
    ],
}
with open(path, "w", encoding="utf-8") as file:
    json.dump(policy, file, indent=2)
PY
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name DataProcessingPolicy --policy-document "file://$POLICY_FILE"
sleep 10

PROCESSOR_ZIP="$STATE_DIR/data_processor.zip"
HANDLER_ZIP="$STATE_DIR/error_handler.zip"
(cd "$SCRIPT_DIR" && zip -q -j "$PROCESSOR_ZIP" data_processor.py && zip -q -j "$HANDLER_ZIP" error_handler.py)

aws lambda create-function \
  --function-name "$PROCESSOR_NAME" \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler data_processor.lambda_handler \
  --zip-file "fileb://$PROCESSOR_ZIP" \
  --timeout 300 \
  --memory-size 512 \
  --environment "Variables={DLQ_URL=$QUEUE_URL}"
aws lambda wait function-active-v2 --function-name "$PROCESSOR_NAME"

aws lambda create-function \
  --function-name "$HANDLER_NAME" \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler error_handler.lambda_handler \
  --zip-file "fileb://$HANDLER_ZIP" \
  --timeout 60 \
  --memory-size 256 \
  --environment "Variables={SNS_TOPIC_ARN=$TOPIC_ARN}"
aws lambda wait function-active-v2 --function-name "$HANDLER_NAME"

HANDLER_ARN="$(aws lambda get-function --function-name "$HANDLER_NAME" --query Configuration.FunctionArn --output text)"
aws lambda create-event-source-mapping \
  --function-name "$HANDLER_NAME" \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 10 \
  --maximum-batching-window-in-seconds 5 \
  --enabled >/dev/null

aws lambda add-permission \
  --function-name "$PROCESSOR_NAME" \
  --statement-id s3-trigger-permission \
  --principal s3.amazonaws.com \
  --action lambda:InvokeFunction \
  --source-arn "arn:aws:s3:::$BUCKET_NAME"

NOTIFICATION_FILE="$STATE_DIR/notification.json"
python3 - "$NOTIFICATION_FILE" "$PROCESSOR_NAME" "$BUCKET_NAME" <<'PY'
import json
import subprocess
import sys

path, function_name, bucket = sys.argv[1:]
function_arn = subprocess.check_output(
    ["aws", "lambda", "get-function", "--function-name", function_name,
     "--query", "Configuration.FunctionArn", "--output", "text"],
    text=True,
).strip()
config = {
    "LambdaFunctionConfigurations": [{
        "Id": "data-processing-notification",
        "LambdaFunctionArn": function_arn,
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {"Key": {"FilterRules": [{"Name": "Prefix", "Value": "data/"}]}},
    }]
}
with open(path, "w", encoding="utf-8") as file:
    json.dump(config, file, indent=2)
PY
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --notification-configuration "file://$NOTIFICATION_FILE"

if [ -n "$ALERT_EMAIL" ]; then
  aws sns subscribe \
    --topic-arn "$TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$ALERT_EMAIL" \
    --region "$AWS_REGION" >/dev/null
fi

cat > "$STATE_DIR/env" <<EOF
export AWS_REGION=$(printf '%q' "$AWS_REGION")
export BUCKET_NAME=$(printf '%q' "$BUCKET_NAME")
export PROCESSOR_NAME=$(printf '%q' "$PROCESSOR_NAME")
export HANDLER_NAME=$(printf '%q' "$HANDLER_NAME")
export DLQ_NAME=$(printf '%q' "$DLQ_NAME")
export QUEUE_URL=$(printf '%q' "$QUEUE_URL")
export QUEUE_ARN=$(printf '%q' "$QUEUE_ARN")
export TOPIC_NAME=$(printf '%q' "$TOPIC_NAME")
export TOPIC_ARN=$(printf '%q' "$TOPIC_ARN")
export ROLE_NAME=$(printf '%q' "$ROLE_NAME")
EOF
chmod 600 "$STATE_DIR/env"
printf 'Created disposable stack with suffix %s. Source %s/env for verification.\n' "$LAB_SUFFIX" "$STATE_DIR"
