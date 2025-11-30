import boto3
import json
import os
import traceback
from botocore.signers import CloudFrontSigner
import rsa
import datetime

dynamodb = boto3.client("dynamodb")
s3 = boto3.client("s3")

TABLE = os.environ["TABLE"]
SHARES_TABLE = os.environ["SHARES_TABLE"]
BUCKET = os.environ["BUCKET"]

CF_DOMAIN = os.environ["CF_DOMAIN"]
CF_KEY_PAIR_ID = os.environ["CF_KEY_PAIR_ID"]
CF_PRIVATE_KEY = os.environ["CF_PRIVATE_KEY"]   # your PEM private key


def rsa_signer(message):
    private_key = rsa.PrivateKey.load_pkcs1(CF_PRIVATE_KEY.encode("utf-8"))
    return rsa.sign(message, private_key, 'SHA-1')


def lambda_handler(event, context):
    try:
        params = event.get("queryStringParameters") or {}
        file_id = params.get("fileId")

        if not file_id:
            return response(400, {"error": "fileId is required"})

        # Get requester from Cognito
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims")
        if not claims or "sub" not in claims:
            return response(401, {"error": "Unauthorized"})
        requester = claims["sub"]

        # ------------------------------------------
        # Check if requester owns or is shared target
        # ------------------------------------------
        metadata = dynamodb.get_item(
            TableName=TABLE,
            Key={"fileId": {"S": file_id}, "userId": {"S": requester}}
        ).get("Item")

        # If not owner, check shares table
        if not metadata:
            shared = dynamodb.query(
                TableName=SHARES_TABLE,
                IndexName="targetUserId_fileId_index",
                KeyConditionExpression="targetUserId = :u AND fileId = :f",
                ExpressionAttributeValues={
                    ":u": {"S": requester},
                    ":f": {"S": file_id}
                }
            ).get("Items")

            if not shared:
                return response(403, {"error": "Not authorized"})

            owner_id = shared[0]["ownerUserId"]["S"]
            metadata = dynamodb.get_item(
                TableName=TABLE,
                Key={"fileId": {"S": file_id}, "userId": {"S": owner_id}}
            ).get("Item")

        # Metadata validation
        if not metadata:
            return response(404, {"error": "File not found"})

        if metadata["status"]["S"] != "ACTIVE":
            return response(409, {"error": "File is not ready for download"})

        s3_key = metadata["s3Key"]["S"]

        # ------------------------------
        # HEAD check to ensure file exists
        # ------------------------------
        try:
            s3.head_object(Bucket=BUCKET, Key=s3_key)
        except Exception:
            return response(500, {"error": "File missing or unavailable in S3"})

        # ------------------------------
        # Build the CloudFront URL
        # ------------------------------
        url = f"https://{CF_DOMAIN}/{s3_key}"

        # Expires in 15 minutes
        expire_time = datetime.datetime.utcnow() + datetime.timedelta(minutes=15)
        expire_timestamp = int(expire_time.timestamp())

        # ------------------------------
        # SIGN THE URL
        # ------------------------------
        signer = CloudFrontSigner(CF_KEY_PAIR_ID, rsa_signer)
        signed_url = signer.generate_presigned_url(
            url,
            date_less_than=expire_time
        )

        return response(200, {
            "downloadUrl": signed_url,
            "expiresIn": 900,
            "fileId": file_id
        })

    except Exception as e:
        traceback.print_exc()
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
