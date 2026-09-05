import json
import logging
import os
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")


def lambda_handler(event, context):
    sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
    if not sns_topic_arn:
        raise RuntimeError("SNS_TOPIC_ARN is not configured")

    records = event.get("Records", [])
    if not records:
        raise ValueError("SQS event contained no Records")

    for record in records:
        message_body = json.loads(record["body"])

        error_message = message_body.get("error_message", "Unknown error")
        timestamp = message_body.get(
            "timestamp",
            datetime.now(timezone.utc).isoformat(),
        )
        retry_count = message_body.get("retry_count", 1)
        original_event = message_body.get("original_event", {})

        s3_details = "S3 details not available"
        original_records = original_event.get("Records", [])

        if original_records:
            try:
                s3_record = original_records[0]["s3"]
                bucket_name = s3_record["bucket"]["name"]
                object_key = s3_record["object"]["key"]
                s3_details = (
                    f"Bucket: {bucket_name}, Object: {object_key}"
                )
            except (KeyError, IndexError, TypeError):
                pass

        alert_message = f"""
Data Processing Error Alert

Error: {error_message}
Timestamp: {timestamp}
Retry Attempt: {retry_count}
{s3_details}

Please investigate the failed processing job.
Check CloudWatch Logs for detailed error information.
""".strip()

        sns.publish(
            TopicArn=sns_topic_arn,
            Message=alert_message,
            Subject="Data Processing Error Alert",
        )

        logger.info("Error alert sent for: %s", error_message)

    return {
        "statusCode": 200,
        "body": json.dumps("Error handling completed"),
    }
