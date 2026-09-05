import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
sqs = boto3.client("sqs")


def lambda_handler(event, context):
    try:
        records = event.get("Records", [])
        if not records:
            raise ValueError("S3 event contained no Records")

        for record in records:
            bucket = record["s3"]["bucket"]["name"]
            key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

            logger.info("Processing object: %s from bucket: %s", key, bucket)

            response = s3.head_object(Bucket=bucket, Key=key)
            file_size = response["ContentLength"]
            last_modified = response["LastModified"]

            if key.endswith(".csv"):
                process_csv_file(key, file_size)
            elif key.endswith(".json"):
                process_json_file(key, file_size)
            else:
                raise ValueError(f"Unsupported file type: {key}")

            create_processing_report(
                bucket=bucket,
                key=key,
                file_size=file_size,
                last_modified=last_modified,
            )

        return {
            "statusCode": 200,
            "body": json.dumps("Successfully processed S3 events"),
        }

    except Exception as exc:
        logger.error("Error processing S3 event: %s", exc)
        send_to_dlq(event, str(exc))
        raise


def process_csv_file(key, file_size):
    logger.info("Processing CSV file: %s (%s bytes)", key, file_size)


def process_json_file(key, file_size):
    logger.info("Processing JSON file: %s (%s bytes)", key, file_size)


def create_processing_report(bucket, key, file_size, last_modified):
    report_key = (
        f"reports/{key.replace('/', '_')}-report-"
        f"{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}.json"
    )

    report = {
        "file_processed": key,
        "file_size": file_size,
        "last_modified": last_modified.isoformat(),
        "processing_time": datetime.now(timezone.utc).isoformat(),
        "status": "completed",
        "processor_version": "1.0",
    }

    s3.put_object(
        Bucket=bucket,
        Key=report_key,
        Body=json.dumps(report, indent=2).encode("utf-8"),
        ContentType="application/json",
    )

    logger.info("Processing report created: %s", report_key)


def send_to_dlq(event, error_message):
    dlq_url = os.environ.get("DLQ_URL")
    if not dlq_url:
        logger.error("DLQ_URL is not configured")
        return

    message = {
        "original_event": event,
        "error_message": error_message,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "retry_count": 1,
    }

    try:
        sqs.send_message(
            QueueUrl=dlq_url,
            MessageBody=json.dumps(message),
        )
        logger.info("Failed event sent to DLQ")
    except Exception as dlq_error:
        logger.error("Failed to send message to DLQ: %s", dlq_error)
