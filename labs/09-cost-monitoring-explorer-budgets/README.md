# Cost monitoring lab: see the spend, then alert before it hurts

## Goal

Prevent unexpected AWS bill spikes with two habits: see where the money goes (Cost Explorer) and get warned before a threshold is crossed (Budgets + SNS). This lab builds a $100 monthly cost budget with graduated alerts at 50%, 75%, and 90% of actual spend, plus one forecast alert at 100% of projected spend.

The transferable pattern is the dependency chain: budget -> thresholds -> notification channel. Notifications cannot be attached before the budget exists, so the order below is not cosmetic.

## Environment

- An AWS account with billing access. Cost Explorer and Budgets are billing services: free LocalStack and AWS Academy Learner Lab do not expose them, so this lab needs a real account you control.
- AWS CLI installed and authenticated.
- An IAM role or user carrying the actions in [`iam-policy.json`](iam-policy.json).

## What this lab builds

| Task | What | Command family |
|---|---|---|
| 1 | Cost Explorer access | `aws ce get-cost-and-usage` |
| 2 | SNS topic + email subscription | `aws sns create-topic` / `subscribe` |
| 3 | Monthly cost budget ($100) | `aws budgets create-budget` |
| 4 | Graduated alerts: ACTUAL 50/75/90% | `aws budgets create-notification` |
| 5 | Forecast alert: FORECASTED 100% | `aws budgets create-notification` |

The scripts in [`scripts/`](scripts/) run the whole chain. Key commands, if you prefer to run them by hand:

```bash
# 1. Cost Explorer (needs a real time period; results fill in over 24h)
aws ce get-cost-and-usage \
    --time-period Start=2026-08-01,End=2026-08-15 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE

# 2. SNS topic and email subscription (confirm the email link!)
aws sns create-topic --name cost-monitoring-alerts
aws sns subscribe --topic-arn <topic-arn> --protocol email --notification-endpoint <you@example.com>

# 3-5. Budget + notifications
# see scripts/setup-budget.sh for the complete flow with a budget JSON file
aws budgets create-budget --account-id <account-id> --budget file://budget-config.json
aws budgets create-notification --account-id <account-id> --budget-name <name> --cli-input-json file://notification.json
```

## IAM policy

The inline policy in [`iam-policy.json`](iam-policy.json) covers exactly the actions the lab needs: read Cost Explorer, manage budgets, and create/subscribe SNS topics.

One trap worth knowing: `budgets:CreateBudget` on an already-existing budget name is treated as an update and requires `budgets:ModifyBudget`. The policy uses `budgets:*` so re-runs and cleanup work without surprises.

## Verification

Read state back, do not trust exit codes:

```bash
# budget exists with the right limit
aws budgets describe-budgets --account-id <account-id>

# exactly 4 notifications: ACTUAL 50/75/90 + FORECASTED 100
aws budgets describe-notifications-for-budget --account-id <account-id> --budget-name <name>

# subscription is confirmed, not PendingConfirmation
aws sns list-subscriptions
```

Cost Explorer shows empty results on a fresh account until up to 24 hours of data accumulate. An empty answer is expected, not an error.

## Cost

Roughly $0 at lab scale: Cost Explorer is free, the first two budgets are within the free tier, and SNS email notifications are free. The only chargeable pieces would be extra budgets beyond the free tier or other notification protocols (SMS, etc.).

## Cleanup

[`scripts/cleanup.sh`](scripts/cleanup.sh) removes the notifications, the budget, and the SNS topic, then confirms both `describe-budgets` and `list-topics` return empty. Cleanup is part of the lab, not optional.

## What this lab teaches

- Billing services are account-level: a real account with billing access is required, and the environment choice matters before you start.
- Dependency order: notifications fail with `NotFoundException` until the budget exists.
- Verification means reading state back, not watching a success message.
- IAM changes propagate slowly: attach the policy, wait, then re-test.
- The graduated-threshold pattern (50/75/90 actual + 100 forecast) transfers directly to CloudWatch alarms and other monitoring.
