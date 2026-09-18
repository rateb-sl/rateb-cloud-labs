# Architecture and evidence map

## Request path

```text
1. EventBridge emits a scheduled event.
2. salesAnalysisReport coordinates the report.
3. The report Lambda reads configuration from Parameter Store.
4. It invokes salesAnalysisReportDataExtractor.
5. The extractor runs inside the café VPC/subnet.
6. The security-group path permits the database connection on TCP 3306.
7. The extractor queries MySQL/MariaDB on the café EC2 host.
8. Grouped rows return to the coordinator.
9. The coordinator formats a message and publishes to SNS.
10. SNS fans out to the confirmed email subscription.
```

## Control-plane versus data-plane reasoning

| Layer | Control-plane declaration | Data-plane question |
|---|---|---|
| IAM | Does Lambda trust and use the expected role? | Did the API call succeed at runtime? |
| Packaging | Is the layer attached? | Did the handler import the client library? |
| VPC | Are subnet and security group selected? | Can the function reach the database host and port? |
| Database | Is a host/parameter configured? | Did the connection authenticate and query return rows? |
| SNS | Does the topic and subscription exist? | Was the message published and delivered to the endpoint? |
| EventBridge | Is the rule enabled and targeted? | Did it fire and produce a report? |

A useful incident question is: **What is the first boundary for which evidence is missing or negative?** Change that boundary only, then re-run the smallest test that can prove it.

## IAM responsibility split

### Report coordinator

- Write CloudWatch logs.
- Read only the required Parameter Store values.
- Invoke only the extractor function.
- Publish only to the report SNS topic.

### Database extractor

- Write CloudWatch logs.
- Create/manage the VPC network interfaces required by a VPC-attached Lambda.
- If it reads parameters directly, read only the required parameter names.

The training exercise used existing roles and managed policies. The public examples in `policies/` show the direction for a production least-privilege review; they are not drop-in replacements for every account.

## Availability and security corrections

- Prefer at least two suitable subnets/AZs for a production VPC-attached Lambda.
- Keep MySQL/MariaDB private.
- Use a source security group rather than `0.0.0.0/0` for database ingress.
- Use encrypted secret storage and rotation.
- Set a bounded timeout based on measured dependency latency, not just the default.
- Add alarms for the coordinator and extractor separately.
- Treat scheduled delivery as at-least-once and design for duplicate notifications.
