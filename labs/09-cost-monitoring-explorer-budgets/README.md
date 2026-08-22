# Cost monitoring: see spend, then alert before it hurts

## Goal

Build a cost-awareness path that combines Cost Explorer for observation with Budgets and SNS for threshold alerts.

The implementation creates a monthly budget with graduated actual-spend thresholds at 50%, 75%, and 90%, plus a 100% forecast threshold.

## Environment

- Real AWS account with billing access
- AWS CLI authenticated
- Cost Explorer and Budgets availability
- SNS email endpoint for notification confirmation
- The included IAM policy for the required service actions

LocalStack and AWS Academy Learner Lab do not provide the billing APIs needed for this lab, so the environment decision is part of the design.

## Dependency model

```text
Cost Explorer observation
        |
SNS topic → confirmed subscription
        |
Budget
        |
actual and forecast notifications
```

Notifications cannot be attached before the budget exists. A rerun of an existing budget may be treated as a modification, so the IAM policy and cleanup path must account for both create and update behavior.

## Implementation

### 1. Inspect cost data

```bash
aws ce get-cost-and-usage \
  --time-period Start=<start-date>,End=<end-date> \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

Cost Explorer data can take time to populate. Empty data is not automatically a failure.

### 2. Create and confirm the notification channel

```bash
aws sns create-topic --name cost-monitoring-alerts
aws sns subscribe --topic-arn <topic-arn> \
  --protocol email \
  --notification-endpoint <you@example.com>
```

The subscription remains ineffective until the recipient confirms it. Read `list-subscriptions` back and distinguish `Confirmed` from `PendingConfirmation`.

### 3. Create the budget and thresholds

The complete scripts are under [`scripts/`](scripts/). The dependency order is:

```bash
aws budgets create-budget --account-id <account-id> --budget file://budget-config.json
aws budgets create-notification --account-id <account-id> --budget-name <name> --cli-input-json file://notification.json
```

Create the budget first, then add three actual thresholds and one forecast threshold.

## Verification

```bash
aws budgets describe-budgets --account-id <account-id>
aws budgets describe-notifications-for-budget \
  --account-id <account-id> \
  --budget-name <name>
aws sns list-subscriptions
```

The target state is one budget with the intended limit, exactly four notifications, and a confirmed email subscription. Read the state back rather than relying on silent create commands.

## Failure boundaries

- `AccessDenied` from Cost Explorer can mean the environment does not expose billing APIs, not that the CLI is broken.
- `NotFoundException` while creating a notification usually means the budget was never created or the name drifted.
- A `PendingConfirmation` SNS subscription means the email link has not been confirmed.
- A stored command or policy with an empty account/name variable can produce misleading downstream errors.

## Cleanup

Cost Explorer is free; budgets and SNS may have account-specific free-tier limits and protocol charges. Cleanup is part of the implementation:

```bash
scripts/cleanup.sh
```

The cleanup script removes notifications, the budget, and the SNS topic, then verifies that the named resources are absent.
