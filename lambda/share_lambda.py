import boto3
import json
import os
import time

dynamodb = boto3.client("dynamodb")

TABLE = os.environ["TABLE"]       # metadata table
SHARES_TABLE = os.environ["SHARES_TABLE"]

def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")

        file_id = body.get("fileId")
        target_user = body.get("targetUserId")

        if not file_id or not target_user:
            return response(400, {"error": "fileId and targetUserId required"})

        # Get requester identity
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims")
        if not claims or "sub" not in claims:
            return response(401, {"error": "Unauthorized"})
        requester = claims["sub"]

        # ---------------------------------------
        # 1. Validate requester owns the file
        # ---------------------------------------
        metadata = dynamodb.get_item(
            TableName=TABLE,
            Key={
                "fileId": {"S": file_id},
                "userId": {"S": requester}
            }
        ).get("Item")

        if not metadata:
            return response(403, {"error": "You do not own this file"})

        # ---------------------------------------
        # 2. Insert sharing entry
        # ---------------------------------------
        shared_at = int(time.time())

        dynamodb.put_item(
            TableName=SHARES_TABLE,
            Item={
                "targetUserId": {"S": target_user},
                "fileId": {"S": file_id},
                "ownerUserId": {"S": requester},
                "sharedAt": {"N": str(shared_at)}
            }
        )

        return response(200, {
            "message": "File shared successfully",
            "fileId": file_id,
            "targetUserId": target_user
        })

    except Exception as e:
        return response(500, {"error": str(e)})


def response(code, body):
    return {
        "statusCode": code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "*"
        },
        "body": json.dumps(body)
    }
