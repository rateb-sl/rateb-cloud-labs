#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$SCRIPT_DIR/.lab-state"
: "${AWS_REGION:=$(aws configure get region 2>/dev/null || true)}"
: "${AWS_REGION:?Set AWS_REGION or run setup first}"

if [ ! -f "$STATE_DIR/env" ]; then
  printf '%s\n' 'No .lab-state/env found; refusing to guess resource names.' >&2
  exit 1
fi
source "$STATE_DIR/env"

MAPPINGS="$(aws lambda list-event-source-mappings --function-name "$HANDLER_NAME" --output json 2>/dev/null || printf '%s' '{"EventSourceMappings":[]}')"
printf '%s' "$MAPPINGS" | python3 -c 'import json,sys; print("\n".join(x["UUID"] for x in json.load(sys.stdin).get("EventSourceMappings", []) if x.get("UUID")))' | while read -r uuid; do
  [ -z "$uuid" ] || aws lambda delete-event-source-mapping --uuid "$uuid" >/dev/null
 done

for function_name in "$PROCESSOR_NAME" "$HANDLER_NAME"; do
  aws lambda delete-function --function-name "$function_name" >/dev/null 2>&1 || true
done

aws s3api put-bucket-notification-configuration --bucket "$BUCKET_NAME" --notification-configuration '{}' >/dev/null 2>&1 || true
VERSIONS="$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json 2>/dev/null || printf '%s' '{}')"
DELETE_PAYLOAD="$(printf '%s' "$VERSIONS" | python3 -c 'import json,sys; d=json.load(sys.stdin); o=[{"Key":x["Key"],"VersionId":x["VersionId"]} for k in ("Versions","DeleteMarkers") for x in d.get(k,[])]; print(json.dumps({"Objects":o,"Quiet":True}))')"
DELETE_COUNT="$(printf '%s' "$DELETE_PAYLOAD" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["Objects"]))')"
if [ "$DELETE_COUNT" -gt 0 ]; then
  aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$DELETE_PAYLOAD" >/dev/null
fi
aws s3api delete-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1 || true

for log_group in "/aws/lambda/$PROCESSOR_NAME" "/aws/lambda/$HANDLER_NAME"; do
  aws logs delete-log-group --log-group-name "$log_group" >/dev/null 2>&1 || true
done
aws sqs delete-queue --queue-url "$QUEUE_URL" >/dev/null 2>&1 || true
aws sns delete-topic --topic-arn "$TOPIC_ARN" >/dev/null 2>&1 || true
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name DataProcessingPolicy >/dev/null 2>&1 || true
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null 2>&1 || true
aws iam delete-role --role-name "$ROLE_NAME" >/dev/null 2>&1 || true

printf '%s\n' 'Cleanup requests completed. Re-run the service-specific read-backs to verify absence.'
