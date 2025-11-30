import boto3
import json
import os

dynamodb = boto3.client("dynamodb")

SHARES_TABLE = os.environ["SHARES_TABLE"]
METADATA_TABLE = os.environ["METADATA_TABLE"]

def lambda_handler(event, context):
    try:
        # ---------------------------------------------
        # 1. Get requester identity
        # ---------------------------------------------
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims")
        if not claims or "sub" not in claims:
            return response(401, {"error": "Unauthorized"})

        user_id = claims["sub"]

        # ---------------------------------------------
        # 2. Query shares table (files shared with me)
        # ---------------------------------------------
        result = dynamodb.query(
            TableName=SHARES_TABLE,
            KeyConditionExpression="targetUserId = :u",
            ExpressionAttributeValues={":u": {"S": user_id}}
        )

        shared_items = result.get("Items", [])

        if not shared_items:
            return response(200, {"files": []})

        # ---------------------------------------------
        # 3. Batch fetch metadata from metadata table
        # ---------------------------------------------
        keys = [
            {
                "fileId": {"S": item["fileId"]["S"]},
                "userId": {"S": item["ownerUserId"]["S"]}
            }
            for item in shared_items
        ]

        batch = dynamodb.batch_get_item(
            RequestItems={
                METADATA_TABLE: {
                    "Keys": keys
                }
            }
        )

        metadata_items = batch["Responses"].get(METADATA_TABLE, [])

        # ---------------------------------------------
        # 4. Merge shares + metadata into final result
        # ---------------------------------------------
        metadata_map = {
            item["fileId"]["S"]: item for item in metadata_items
        }

        files = []
        for share in shared_items:
            fid = share["fileId"]["S"]
            if fid not in metadata_map:
                continue

            meta = metadata_map[fid]

            files.append({
                "fileId": fid,
                "filename": meta["filename"]["S"],
                "ownerUserId": share["ownerUserId"]["S"],
                "sharedAt": int(share["sharedAt"]["N"]),
                "createdAt": int(meta["createdAt"]["N"]),
                "status": meta["status"]["S"]
            })

        return response(200, {"files": files})

    except Exception as e:
        return response(500, {"error": str(e)})


def response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "*"
        },
        "body": json.dumps(body)
    }
