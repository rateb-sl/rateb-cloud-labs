# Troubleshooting evidence ladder

Use the first failed boundary, not the loudest symptom.

## 1. Extractor timeout

**Observed pattern:** the extractor timed out after 3 seconds before returning a result.

**Most useful checks:**

```bash
aws lambda get-function-configuration \
  --function-name "$EXTRACTOR_FUNCTION" \
  --query '{Runtime:Runtime,Handler:Handler,Timeout:Timeout,Layers:Layers,VpcConfig:VpcConfig}'
```

Then inspect the selected security group and verify the intended TCP 3306 path. A timeout is usually a reachability or connection-completion problem before it is an IAM problem.

**Evidence boundary:** configuration output proves declared settings; it does not prove a successful TCP handshake.

## 2. Empty extractor result

A successful response with an empty list can mean the query worked against an empty order table. Place controlled test data and re-run. Compare the returned schema and rows, not only the HTTP-style status code.

## 3. Malformed topic ARN

**Observed pattern:**

```text
IndexError: list index out of range
TOPIC_REGION = arnParts[3]
```

**Interpretation:** the report function was parsing a missing, truncated, or wrong resource identifier. Check the environment variable key and the complete SNS ARN without printing the value into logs.

## 4. Report timeout

The coordinator has more work than the extractor alone: parameter reads, Lambda invocation, response handling, formatting, and SNS publication. The default three-second timeout was insufficient in the training run. Increase it only after checking logs and dependency behavior; do not use a large timeout to hide a persistent network or permission failure.

## 5. Notification boundary

Separate these checks:

1. `sns:Publish` was authorized.
2. The topic accepted the message.
3. The subscription was confirmed.
4. The recipient endpoint received the message.

A publish response cannot prove the final email was delivered.

## 6. Scheduled invocation

Verify all of the following:

- rule is enabled;
- expression is UTC and has the intended day-of-week;
- Lambda target is attached;
- Lambda invocation log exists at the scheduled time;
- report output is present;
- recipient delivery is confirmed.

## Secure troubleshooting rules

- Do not print database passwords, access keys, secret values, or full live ARNs.
- Do not open database port 3306 globally in production.
- Do not retry a notification blindly without considering duplicates.
- Do not call a configuration screenshot proof of an end-to-end result.
