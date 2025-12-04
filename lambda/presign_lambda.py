import boto3
import json
import time
import uuid
import os
from decimal import Decimal

s3 = boto3.client('s3')
dynamodb = boto3.client('dynamodb')

BUCKET = os.environ['BUCKET']
TABLE = os.environ['TABLE']
USERS_TABLE = os.environ['USERS_TABLE']

MAX_QUOTA = 50 * 1024 * 1024  # 50 MB


def lambda_handler(event, context):
    body = json.loads(event.get("body", "{}"))

    filename = body.get("filename")
    size_bytes = int(body["sizeBytes"])

    if not filename or size_bytes is None:
        return response(400, {"error": "filename and sizeBytes are required"})

    # user identity
    auth = event.get("requestContext", {}).get("authorizer", {})
    claims = auth.get("claims")

    if not claims:
        return response(401, {"error": "Missing Cognito authorizer claims"})
    user_id = auth.get("claims", {}).get("sub")

    # -----------------------------
    # 1. Get current user quota
    # -----------------------------
    user_item = dynamodb.get_item(
        TableName=USERS_TABLE,
        Key={"userId": {"S": user_id}}
    ).get("Item")

    used_bytes = int(user_item["usedBytes"]["N"]) if user_item else 0

    # -----------------------------
    # 2. Check quota
    # -----------------------------
    if used_bytes + size_bytes > MAX_QUOTA:
        return response(403, {"error": "User quota exceeded"})

    # -----------------------------
    # 3. Reserve quota (atomic)
    # -----------------------------
    try:
        remaining_quota = MAX_QUOTA - size_bytes

        dynamodb.update_item(
            TableName=USERS_TABLE,
            Key={"userId": {"S": user_id}},
            UpdateExpression="SET usedBytes = if_not_exists(usedBytes, :zero) + :inc",
            ConditionExpression="attribute_not_exists(usedBytes) OR usedBytes <= :remaining",
            ExpressionAttributeValues={
                ":inc": {"N": str(size_bytes)},
                ":zero": {"N": "0"},
                ":remaining": {"N": str(remaining_quota)}
            }
        )

    except Exception as e:
        return response(403, {"error": "User Table Update Error"})

    # -----------------------------
    # 4. Create metadata (PENDING)
    # -----------------------------
    file_id = str(uuid.uuid4())
    s3_key = f"{user_id}/{file_id}/{filename}"
    created_at = int(time.time())

    dynamodb.put_item(
        TableName=TABLE,
        Item={
            "fileId": {"S": file_id},
            "userId": {"S": user_id},
            "filename": {"S": filename},
            "s3Key": {"S": s3_key},
            "createdAt": {"S": str(created_at)},
            "sizeBytes": {"N": str(size_bytes)},
            "status": {"S": "PENDING"}
        }
    )

    # -----------------------------
    # 5. Generate presigned URL
    # -----------------------------
    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET, "Key": s3_key},
        ExpiresIn=900
    )

    return response(200, {
        "fileId": file_id,
        "uploadUrl": upload_url,
        "expiresIn": 900
    })


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }
