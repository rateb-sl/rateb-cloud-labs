"""Redirect a short code to the original URL stored in DynamoDB."""

import json
import os

import boto3


TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def lambda_handler(event, context):
    path_parameters = event.get("pathParameters") or {}
    short_code = path_parameters.get("shortCode")
    if not short_code:
        return {"statusCode": 400, "body": json.dumps({"error": "Missing short code"})}

    item = table.get_item(Key={"shortCode": short_code}).get("Item")
    if not item:
        return {"statusCode": 404, "body": json.dumps({"error": "Not found"})}

    return {
        "statusCode": 302,
        "headers": {"Location": item["originalUrl"]},
        "body": "",
    }
