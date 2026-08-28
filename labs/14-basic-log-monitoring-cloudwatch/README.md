# Basic log monitoring with CloudWatch: turn log text into an alerting path

## Goal

Build and verify a small serverless monitoring path for application errors:

```text
CloudWatch Logs → metric filter → custom metric → CloudWatch alarm
                                                     ↓
                                                    SNS
                                                     ↓
                                            email + Lambda processor
```

The transferable pattern is **log event → measurable signal → threshold decision → fan-out → action**. The important engineering lesson is that each relationship needs its own read-back; creating an alarm does not prove that logs are being counted, and a Lambda invocation does not prove that a human notification was delivered.

## Environment

- AWS CLI v2 from a local Mac Terminal
- Personal Free Tier account; Region `eu-central-1`
- CloudWatch Logs, CloudWatch custom metrics and alarm, SNS, Lambda, and IAM
- Lambda runtime `python3.13`
- No EC2 instance or SSH connection was required
- Disposable resource names used for this lab; all resources were removed after verification

The public artifact contains placeholders only. It does not include account IDs, real ARNs, email addresses, credentials, IP addresses, or private files.

## Architecture and dependency order

```text
Plain-text application log
        │
        ▼
/aws/application/monitoring-demo
        │  filter: ?ERROR ?FAILED ?EXCEPTION ?TIMEOUT
        ▼
CustomApp/Monitoring : ApplicationErrors
        │  Sum > 2 in a 300-second period
        ▼
application-errors-alarm
        │
        ▼
log-monitoring-alerts (SNS)
        ├── email subscription
        └── Lambda subscription
                  │
                  ▼
          /aws/lambda/log-processor
```

The setup order was:

1. Create the application log group and set retention.
2. Add the metric filter.
3. Create the SNS topic.
4. Create the Lambda execution role and function.
5. Subscribe Lambda to SNS and grant SNS permission to invoke it.
6. Create the alarm with the SNS topic as its action.
7. Ingest fresh test events and verify each downstream layer.

The cleanup order was the reverse dependency direction: alarm → metric filter → Lambda → IAM policy/role → SNS topic → log groups.

## Implementation and key commands

The following is the sanitized command path used for the live run. Run it only in a disposable account and review every name before changing AWS state.

### 1. Establish the context

```bash
set -euo pipefail

export AWS_REGION="eu-central-1"
export AWS_DEFAULT_REGION="$AWS_REGION"

aws --version
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
aws configure get region
```

The identity check proves which principal is operating the lab. It does not prove that the principal has every later permission; each service operation still needs a read-back.

### 2. Create the log group and retention policy

```bash
LOG_GROUP_NAME="/aws/application/monitoring-demo"

aws logs create-log-group \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME"

aws logs put-retention-policy \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME" \
  --retention-in-days 7

aws logs describe-log-groups \
  --region "$AWS_REGION" \
  --log-group-name-prefix "$LOG_GROUP_NAME" \
  --query 'logGroups[?logGroupName==`/aws/application/monitoring-demo`].{Name:logGroupName,RetentionDays:retentionInDays}' \
  --output table
```

Expected evidence is one row with the exact name and `RetentionDays` equal to `7`. A row with `RetentionDays: None` is only a partial pass; retention must be configured before proceeding.

### 3. Add a metric filter for the actual event shape

The test messages were plain text, not JSON. Therefore the filter used optional plain-text terms rather than a JSON-only pattern.

```bash
METRIC_FILTER_NAME="error-count-filter"
METRIC_NAMESPACE="CustomApp/Monitoring"
METRIC_NAME="ApplicationErrors"

aws logs put-metric-filter \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME" \
  --filter-name "$METRIC_FILTER_NAME" \
  --filter-pattern '?ERROR ?FAILED ?EXCEPTION ?TIMEOUT' \
  --metric-transformations \
    metricName="$METRIC_NAME",metricNamespace="$METRIC_NAMESPACE",metricValue=1,defaultValue=0

aws logs describe-metric-filters \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME" \
  --filter-name-prefix "$METRIC_FILTER_NAME" \
  --query 'metricFilters[].{Filter:filterName,Pattern:filterPattern,Metric:metricTransformations[0].metricName,Namespace:metricTransformations[0].metricNamespace}' \
  --output table
```

The filter configuration is not retroactive. This read-back proves the filter exists, not that it has emitted a datapoint.

### 4. Create the notification topic

```bash
SNS_TOPIC_NAME="log-monitoring-alerts"
ALERT_EMAIL="<you@example.com>"

SNS_TOPIC_ARN="$(aws sns create-topic \
  --region "$AWS_REGION" \
  --name "$SNS_TOPIC_NAME" \
  --query 'TopicArn' \
  --output text)"

aws sns subscribe \
  --region "$AWS_REGION" \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$ALERT_EMAIL"

aws sns get-topic-attributes \
  --region "$AWS_REGION" \
  --topic-arn "$SNS_TOPIC_ARN" \
  --query 'Attributes.{TopicArn:TopicArn,SubscriptionsConfirmed:SubscriptionsConfirmed}' \
  --output table
```

The endpoint is intentionally a placeholder. The live run used a private email address and the owner confirmed receipt; neither is included here. Email confirmation is a human-endpoint check, separate from the topic's existence.

### 5. Create the Lambda processor

`log_processor.py` was the function module used by the live run:

```python
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    for record in event.get("Records", []):
        message = record.get("Sns", {}).get("Message", "{}")
        try:
            alarm = json.loads(message)
        except json.JSONDecodeError:
            alarm = {}

        alarm_name = alarm.get("AlarmName", "unknown")
        state = alarm.get("NewStateValue", "unknown")
        logger.info("Processing alarm: %s", alarm_name)
        logger.info("State: %s", state)

    return {"statusCode": 200, "body": "processed"}
```

Create a Lambda trust policy locally, create the role, and attach only the basic execution policy:

```bash
ROLE_NAME="lambda-log-processor-role"
FUNCTION_NAME="log-processor"
HANDLER="log_processor.lambda_handler"

cat > /tmp/lambda-trust-policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

python3 -m json.tool /tmp/lambda-trust-policy.json >/dev/null

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

ROLE_ARN="$(aws iam get-role \
  --role-name "$ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)"

cd /tmp
zip -q -j /tmp/log-processor.zip /tmp/log_processor.py

aws lambda create-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --runtime python3.13 \
  --role "$ROLE_ARN" \
  --handler "$HANDLER" \
  --zip-file fileb:///tmp/log-processor.zip
```

The role trust relationship lets Lambda assume the role. The attached AWS-managed policy lets the function write its own CloudWatch Logs. Neither proves that SNS can invoke the function; that requires a separate permission and subscription.

### 6. Connect SNS to Lambda

```bash
LAMBDA_FUNCTION_ARN="$(aws lambda get-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --query 'Configuration.FunctionArn' \
  --output text)"

aws lambda add-permission \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --statement-id sns-invoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn "$SNS_TOPIC_ARN"

aws sns subscribe \
  --region "$AWS_REGION" \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol lambda \
  --notification-endpoint "$LAMBDA_FUNCTION_ARN"

aws sns list-subscriptions-by-topic \
  --region "$AWS_REGION" \
  --topic-arn "$SNS_TOPIC_ARN" \
  --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}' \
  --output table
```

The subscription row proves the SNS-to-Lambda relationship was registered. Lambda execution logs later prove that a notification actually reached the function.

### 7. Create the alarm

```bash
ALARM_NAME="application-errors-alarm"

aws cloudwatch put-metric-alarm \
  --region "$AWS_REGION" \
  --alarm-name "$ALARM_NAME" \
  --alarm-description "Alarm when application error count exceeds two" \
  --namespace "$METRIC_NAMESPACE" \
  --metric-name "$METRIC_NAME" \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 2 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data missing \
  --alarm-actions "$SNS_TOPIC_ARN"

aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Threshold:Threshold,Period:Period,Actions:AlarmActions}' \
  --output table
```

The alarm evaluates the sum of the custom metric over a five-minute period. It should not be expected to enter `ALARM` until fresh matching log events create a datapoint.

### 8. Ingest three fresh error events

```bash
LOG_STREAM_NAME="test-stream"

aws logs create-log-stream \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME" \
  --log-stream-name "$LOG_STREAM_NAME"

for i in 1 2 3; do
  TIMESTAMP="$(date +%s)000"
  aws logs put-log-events \
    --region "$AWS_REGION" \
    --log-group-name "$LOG_GROUP_NAME" \
    --log-stream-name "$LOG_STREAM_NAME" \
    --log-events "[{\"timestamp\":$TIMESTAMP,\"message\":\"ERROR: Database connection failed - test event $i\"}]"
done
```

The three messages intentionally contain the literal `ERROR` term expected by the filter. The live run recorded all three events in `test-stream`.

## Verification

### Metric datapoint

```bash
START_TIME="$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ')"
END_TIME="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

aws cloudwatch get-metric-data \
  --region "$AWS_REGION" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --metric-data-queries '[{"Id":"applicationerrors","MetricStat":{"Metric":{"Namespace":"CustomApp/Monitoring","MetricName":"ApplicationErrors"},"Period":60,"Stat":"Sum"},"ReturnData":true}]' \
  --query 'MetricDataResults[].{Id:Id,Status:StatusCode,Values:Values}' \
  --output table
```

Observed result: `Status: Complete` and `ApplicationErrors` value `3.0`. This independently proves that the three fresh matching events became metric data.

### Alarm state and notification processing

```bash
aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-names "$ALARM_NAME" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason,Threshold:Threshold}' \
  --output table

aws logs filter-log-events \
  --region "$AWS_REGION" \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" \
  --filter-pattern 'Processing alarm OR State:' \
  --query 'events[].message' \
  --output text
```

Observed results:

| Layer | Observed evidence | What it proves |
| --- | --- | --- |
| Log ingestion | Three `ERROR: Database connection failed - test event N` events in `test-stream` | Fresh source events existed in the monitored log group |
| Custom metric | `ApplicationErrors = 3.0`, status `Complete` | The filter matched all three events |
| Alarm | `ALARM`, threshold `2.0`, metric value `3.0` | CloudWatch evaluated `3.0 > 2.0` |
| Lambda | `Processing alarm: application-errors-alarm`; `State: ALARM` | SNS delivered the alarm notification to Lambda and the function processed it |
| Human endpoint | Email delivery confirmed by the account owner | The notification path reached the intended private endpoint |

The Lambda log group and stream initially showed `StoredBytes: 0` in metadata read-backs; that is not a failure signal by itself. The execution-log entries are the stronger proof of invocation and processing.

## Failure handled during the run

The first all-at-once cleanup attempt returned:

```text
InvalidParameter: Invalid parameter: Topic Name
```

The error was isolated to SNS topic deletion. The correction was to resolve the exact ARN from `list-topics`, pass that ARN to `delete-topic`, and run a separate final inventory check. The final check returned no matching `log-monitoring-alerts` topic, and the other resource inventories were also empty.

This matters because a compound shell block can continue after a non-fatal command error. A trailing success message is not cleanup evidence; an independent names-only read-back is.

## Cost and safety

- No EC2 instance, NAT Gateway, RDS database, or other intentionally expensive resource was used.
- Lambda and CloudWatch/SNS usage for this small test was expected to remain within normal Free Tier/low-usage limits, but Free Tier is not a guarantee of zero cost.
- SNS email confirmation and Lambda log retention can create ongoing state if resources are left behind.
- The live run removed all created resources and verified the final empty state.
- The public README uses placeholders and does not expose the private endpoint used during the test.

## Cleanup

Run cleanup only after the alarm, metric datapoint, Lambda processing, and email checks are complete. Names below match the disposable lab resources.

```bash
set -euo pipefail

export AWS_REGION="eu-central-1"
ALARM_NAME="application-errors-alarm"
METRIC_FILTER_NAME="error-count-filter"
LOG_GROUP_NAME="/aws/application/monitoring-demo"
FUNCTION_NAME="log-processor"
ROLE_NAME="lambda-log-processor-role"
SNS_TOPIC_NAME="log-monitoring-alerts"

aws cloudwatch delete-alarms \
  --region "$AWS_REGION" \
  --alarm-names "$ALARM_NAME" || true

aws logs delete-metric-filter \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME" \
  --filter-name "$METRIC_FILTER_NAME" || true

aws lambda delete-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" || true

aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true

aws iam delete-role \
  --role-name "$ROLE_NAME" || true

SNS_TOPIC_ARN="$(aws sns list-topics \
  --region "$AWS_REGION" \
  --query "Topics[?ends_with(TopicArn, ':$SNS_TOPIC_NAME')].TopicArn | [0]" \
  --output text)"

if [[ -n "$SNS_TOPIC_ARN" && "$SNS_TOPIC_ARN" != "None" ]]; then
  aws sns delete-topic \
    --region "$AWS_REGION" \
    --topic-arn "$SNS_TOPIC_ARN"
fi

aws logs delete-log-group \
  --region "$AWS_REGION" \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" || true

aws logs delete-log-group \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP_NAME" || true
```

Verify every dependency-sensitive surface independently:

```bash
aws cloudwatch describe-alarms --region "$AWS_REGION" --alarm-names "$ALARM_NAME" --output table
aws logs describe-metric-filters --region "$AWS_REGION" --log-group-name "$LOG_GROUP_NAME" --filter-name-prefix "$METRIC_FILTER_NAME" --output table
aws lambda get-function --region "$AWS_REGION" --function-name "$FUNCTION_NAME" --output table
aws iam get-role --role-name "$ROLE_NAME" --output table
aws sns list-topics --region "$AWS_REGION" --query "Topics[?ends_with(TopicArn, ':$SNS_TOPIC_NAME')].TopicArn" --output table
aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP_NAME" --output table
aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "/aws/lambda/$FUNCTION_NAME" --output table
```

Expected cleanup evidence is empty output, an empty table, or a not-found response for each target. In the live run, all final inventories were empty after the exact-ARN SNS correction.

## What this lab teaches

1. **A metric filter is a contract with the log format.** Plain-text events need a plain-text pattern; a JSON filter cannot be assumed to match them.
2. **CloudWatch monitoring is a chain, not a single resource.** Verify log ingestion, filter configuration, datapoints, alarm evaluation, fan-out, and consumer execution separately.
3. **SNS is a fan-out boundary.** The topic can deliver to human and machine consumers, but each subscription and permission relationship needs its own evidence.
4. **IAM trust and permissions are different.** Lambda must be able to assume its role, and the role must be able to write execution logs; SNS must separately be allowed to invoke the function.
5. **Cleanup is an operational test.** Exact-resource read-backs, especially after a deletion error, are more trustworthy than a shell script's final status message.
6. **The production extension is obvious.** Add structured JSON logs, dimensions with care, dashboards, runbooks, deduplication, dead-letter handling, and alert-quality controls before using this pattern for a high-volume service.
