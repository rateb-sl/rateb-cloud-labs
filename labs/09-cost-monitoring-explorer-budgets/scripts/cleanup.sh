#!/usr/bin/env bash
# Cost monitoring lab cleanup: remove notifications, budget, and SNS topic,
# then verify nothing is left.
# Usage:
#   export ACCOUNT_ID=<12-digit account id>
#   export BUDGET_NAME=MonthlyCostBudget
#   ./cleanup.sh
set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:?set ACCOUNT_ID}"
BUDGET_NAME="${BUDGET_NAME:-MonthlyCostBudget}"

# Notifications must be deleted one by one (no bulk delete).
for spec in \
    'NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=50.0,ThresholdType=PERCENTAGE' \
    'NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=75.0,ThresholdType=PERCENTAGE' \
    'NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=90.0,ThresholdType=PERCENTAGE' \
    'NotificationType=FORECASTED,ComparisonOperator=GREATER_THAN,Threshold=100.0,ThresholdType=PERCENTAGE'
do
    aws budgets delete-notification --account-id "${ACCOUNT_ID}" \
        --budget-name "${BUDGET_NAME}" --notification "${spec}" || true
done
echo "notifications deleted"

aws budgets delete-budget --account-id "${ACCOUNT_ID}" --budget-name "${BUDGET_NAME}"
echo "budget deleted"

TOPIC_ARN=$(aws sns list-topics --query 'Topics[0].TopicArn' --output text 2>/dev/null || true)
if [ -n "${TOPIC_ARN}" ] && [ "${TOPIC_ARN}" != "None" ]; then
    aws sns delete-topic --topic-arn "${TOPIC_ARN}"
    echo "topic deleted: ${TOPIC_ARN}"
else
    echo "no topic found"
fi

# Verify the account is back to its starting state.
echo "--- remaining budgets (expect none) ---"
aws budgets describe-budgets --account-id "${ACCOUNT_ID}"
echo "--- remaining topics (expect none) ---"
aws sns list-topics
echo "cleanup complete"
