#!/usr/bin/env bash
# Cost monitoring lab: SNS topic + budget + 4 notifications.
# Reference script, deliberately without hard-coded identifiers.
# Usage:
#   export ACCOUNT_ID=<12-digit account id>
#   export EMAIL=<you@example.com>
#   export BUDGET_NAME=MonthlyCostBudget   # optional, default below
#   ./setup-budget.sh
set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:?set ACCOUNT_ID, e.g. from: aws sts get-caller-identity --query Account --output text}"
EMAIL="${EMAIL:?set EMAIL to receive the budget alerts}"
BUDGET_NAME="${BUDGET_NAME:-MonthlyCostBudget}"

# --- Task 2: SNS topic + email subscription -------------------------------
TOPIC_ARN=$(aws sns create-topic --name cost-monitoring-alerts --query TopicArn --output text)
echo "topic created: ${TOPIC_ARN}"
aws sns subscribe --topic-arn "${TOPIC_ARN}" --protocol email --notification-endpoint "${EMAIL}" >/dev/null
echo "email subscription created: confirm the link in the email (otherwise it stays PendingConfirmation)"

# --- Task 3: monthly cost budget ------------------------------------------
cat > budget-config.json <<EOF
{
    "BudgetName": "${BUDGET_NAME}",
    "BudgetLimit": { "Amount": "100.00", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "TimePeriod": { "Start": "$(date +%Y-%m-01)T00:00:00Z", "End": "2087-06-15T00:00:00Z" },
    "BudgetType": "COST",
    "CostFilters": {},
    "CostTypes": {
        "IncludeTax": true, "IncludeSubscription": true, "UseBlended": false,
        "IncludeRefund": false, "IncludeCredit": false, "IncludeUpfront": true,
        "IncludeRecurring": true, "IncludeOtherSubscription": true,
        "IncludeSupport": true, "IncludeDiscount": true, "UseAmortized": false
    }
}
EOF
aws budgets create-budget --account-id "${ACCOUNT_ID}" --budget file://budget-config.json
echo "budget created: ${BUDGET_NAME}"

# --- Tasks 4 + 5: graduated actual alerts + forecast alert ----------------
for spec in \
    'ACTUAL 50.0 notification-50.json' \
    'ACTUAL 75.0 notification-75.json' \
    'ACTUAL 90.0 notification-90.json' \
    'FORECASTED 100.0 notification-forecast.json'
do
    set -- ${spec}
    TYPE="$1"; THRESHOLD="$2"; FILE="$3"
    cat > "${FILE}" <<EOF
{
    "Notification": {
        "NotificationType": "${TYPE}",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": ${THRESHOLD},
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
    },
    "Subscribers": [
        { "SubscriptionType": "SNS", "Address": "${TOPIC_ARN}" }
    ]
}
EOF
    aws budgets create-notification --account-id "${ACCOUNT_ID}" \
        --budget-name "${BUDGET_NAME}" --cli-input-json "file://${FILE}"
    echo "notification added: ${TYPE} ${THRESHOLD}%"
done

rm -f budget-config.json notification-*.json
echo "done: budget ${BUDGET_NAME} with 4 notifications"
