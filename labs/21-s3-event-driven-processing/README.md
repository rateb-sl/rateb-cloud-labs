# S3 event-driven processing: route success and failure separately

## Goal

Build an event-driven file-processing path with two distinct outcomes:

```text
S3 upload under data/
        │
        ▼
processing Lambda
   ┌────┴────┐
 success     failure
   │            │
   ▼            ▼
report in S3  structured message in SQS
                  │
                  ▼
          error-handler Lambda
                  │
                  ▼
                 SNS
```

The transferable lesson is **dependency-ordered event wiring**. An event source, permission, function, queue, and notification topic can all exist while the end-to-end path is still broken. Each relationship needs a read-back and a real test event.

## Environment

- AWS CLI v2 from a local macOS Terminal
- Disposable AWS account and Region `eu-central-1`
- S3, Lambda, SQS, SNS, IAM, and CloudWatch Logs
- Lambda runtime `python3.12`
- The live run used generated names and removed them after verification
- Public files contain placeholders only: no account IDs, real ARNs, email addresses, credentials, IPs, or private state

## Architecture and dependency order

1. Create the versioned S3 bucket.
2. Create the SNS topic and optional email subscription.
3. Create the SQS queue used as the structured failure queue.
4. Create the Lambda trust role and execution permissions.
5. Deploy the processing and error-handler functions.
6. Connect SQS to the error handler with an event-source mapping.
7. Grant S3 permission to invoke the processing Lambda.
8. Configure the S3 notification with the `data/` prefix.
9. Test a valid CSV and an unsupported file.
10. Delete and verify every lab resource.

The `reports/` prefix prevents generated reports from retriggering the `data/` notification.

## Repository files

- [`data_processor.py`](data_processor.py) — validates the S3 event, handles CSV/JSON files, writes reports, and sends structured failures to SQS.
- [`error_handler.py`](error_handler.py) — consumes SQS failure messages and publishes an operational alert to SNS.
- [`policies/trust-policy.json`](policies/trust-policy.json) — Lambda trust relationship.
- [`policies/execution-policy.template.json`](policies/execution-policy.template.json) — least-privilege policy template. Replace placeholders before use.
- [`scripts/setup.sh`](scripts/setup.sh) — creates and wires a disposable stack.
- [`scripts/cleanup.sh`](scripts/cleanup.sh) — removes the stack, including versioned S3 objects and CloudWatch log groups.

## Implementation

### 1. Preflight

```bash
export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
export AWS_DEFAULT_REGION="$AWS_REGION"
aws --version
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
```

The identity check proves which principal is operating the lab. It does not prove that the principal has every later permission.

### 2. Create the disposable stack

Use a unique suffix once and preserve it for the entire run. The setup script generates the bucket, Lambda, queue, topic, and role names from the same suffix:

```bash
export AWS_REGION="eu-central-1"
export ALERT_EMAIL="<you@example.com>"
./scripts/setup.sh
```

The email is optional for the infrastructure path. If used, confirmation is a separate human-endpoint check; topic creation and SNS publish success do not prove email delivery.

Important implementation details:

- SQS uses the valid `VisibilityTimeout=300` attribute.
- The processing role needs both SQS producer permission and SQS consumer permissions because the Lambda event-source mapping polls the queue.
- S3 invokes Lambda through a resource-based Lambda permission, not only through the Lambda execution role.
- The S3 notification is restricted to `data/`.

### 3. Test the success path

```bash
printf '%s\n' \
  'name,age,city' \
  'John,30,New York' \
  'Jane,25,Los Angeles' \
  > /tmp/test-data.csv

aws s3 cp /tmp/test-data.csv "s3://${BUCKET_NAME}/data/test-data.csv"
```

Verify both the object and the generated report. The report must identify `data/test-data.csv` and show `status: completed`. CloudWatch should contain a message similar to:

```text
Processing object: data/test-data.csv from bucket: <bucket-name>
```

### 4. Test the failure path

```bash
printf '%s\n' 'unsupported test input' > /tmp/failure-test.txt
aws s3 cp /tmp/failure-test.txt "s3://${BUCKET_NAME}/data/failure-test.txt"
```

The `.txt` suffix intentionally exercises the rejection branch. Verify all three layers:

| Layer | Evidence |
| --- | --- |
| Processing Lambda | `Unsupported file type: data/failure-test.txt` in CloudWatch Logs |
| Error handler | `Error alert sent for: Unsupported file type: data/failure-test.txt` in CloudWatch Logs |
| SQS | Queue returns to zero after the enabled event-source mapping consumes the message |

A zero-message queue is not evidence that no failure occurred; in this design it can mean the error handler already consumed the message.

### 5. Verify the wiring

```bash
aws s3api get-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --query 'LambdaFunctionConfigurations[].{Id:Id,Events:Events,Filter:Filter}' \
  --output json

aws lambda list-event-source-mappings \
  --function-name "$ERROR_HANDLER_NAME" \
  --query 'EventSourceMappings[].{State:State,BatchSize:BatchSize,BatchingWindow:MaximumBatchingWindowInSeconds}' \
  --output json
```

The S3 filter should contain a `Prefix` rule with value `data/`. The SQS mapping should be `Enabled`. `LastProcessingResult` may remain `null` in the mapping read-back even after a successful run; the handler's CloudWatch log is the stronger proof that a message was consumed and processed.

## Observed live-run evidence

The live run completed on 2026-09-05 with the following evidence:

- S3 notification existed with `s3:ObjectCreated:*` and prefix `data/`.
- Valid CSV processing produced a report with:
  - `file_processed: data/test-data.csv`
  - `status: completed`
  - `processor_version: 1.0`
- Processing Lambda logged `Processing object: data/test-data.csv`.
- Unsupported input produced `Unsupported file type: data/failure-test.txt`.
- Error handler logged `Error alert sent for: Unsupported file type: data/failure-test.txt`.
- The queue had zero visible and zero not-visible messages after consumption.
- The event-source mapping was `Enabled`, with batch size `10` and batching window `5` seconds.
- The SNS email confirmation page was received, but a later AWS subscription read-back returned `Deleted`; email delivery was therefore not independently verified.
- Cleanup was verified: bucket, both functions, queue, topic, IAM role, and both Lambda log groups were absent.

## Failure boundaries and design lessons

- A successful S3 upload proves storage, not processing.
- A Lambda `Active` state proves readiness, not event delivery.
- An S3 notification must be paired with a Lambda resource-based invoke permission.
- An SQS event-source mapping is a managed poller and needs receive/delete/visibility permissions.
- A consumed queue may be empty even though the failure path worked.
- SNS `Publish` success does not prove an email endpoint delivered the message.
- This implementation sends a structured failure to SQS and then re-raises the exception. In production, choose deliberately between a custom structured queue path and Lambda's asynchronous dead-letter destination, or make the error handler understand both formats to avoid duplicate alerts.

## Cleanup

Run cleanup after the test. The script removes the notification, all versioned S3 objects and delete markers, both Lambda functions, their log groups, the event-source mapping, the queue, the topic, and the IAM role:

```bash
./scripts/cleanup.sh
```

Verify absence rather than trusting a successful delete response. A clean closeout means no bucket, Lambda function, queue, topic, IAM role, event-source mapping, or lab log group remains.

## What this lab teaches

- Event-driven systems are dependency graphs, not isolated resources.
- IAM has two relevant permission surfaces here: execution-role permissions and resource-based S3 invoke permission.
- SQS provides durable failure handoff; the error handler provides operational response; SNS provides fan-out.
- Verification must follow the event through every boundary.
- Cleanup is part of correctness because temporary cloud resources have an ongoing cost and security footprint.
