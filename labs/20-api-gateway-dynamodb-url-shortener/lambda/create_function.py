"""Create a short URL mapping in DynamoDB."""

import json
import os
import uuid

import boto3


TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON"})}

    original_url = body.get("url")
    if not isinstance(original_url, str) or not original_url.startswith(("http://", "https://")):
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "url must be an HTTP(S) URL"}),
        }

    short_code = uuid.uuid4().hex[:6]
    table.put_item(Item={"shortCode": short_code, "originalUrl": original_url})

    return {
        "statusCode": 200,
        "body": json.dumps({"shortCode": short_code}),
    }
