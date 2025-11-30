import boto3
import os
import traceback

s3 = boto3.client("s3")
dynamodb = boto3.client("dynamodb")

TABLE = os.environ["TABLE"]  # metadata table


def lambda_handler(event, context):
    try:
        for record in event["Records"]:
            if record["eventSource"] != "aws:s3":
                continue

            bucket = record["s3"]["bucket"]["name"]
            key = record["s3"]["object"]["key"]

            # Example key format:
            #   userId/fileId/filename.ext
            key_parts = key.split("/")
            if len(key_parts) < 3:
                print(f"Invalid key format: {key}")
                continue

            user_id = key_parts[0]
            file_id = key_parts[1]

            print(f"Processing upload: user={user_id} file={file_id}")

            # ---------------------------------------------------
            # 1. HEAD the object to get actual size + checksum
            # ---------------------------------------------------
            try:
                head = s3.head_object(Bucket=bucket, Key=key)
                actual_size = head["ContentLength"]
                etag = head["ETag"].replace('"', "")  # checksum
                # --- QUOTA CORRECTION LOGIC (insert here) ---

                # Load reserved size from metadata (from DynamoDB)
                reserved_size = int(metadata["sizeBytes"]["N"])

                # If actual size differs from reported size, adjust user quota
                if actual_size != reserved_size:
                    diff = actual_size - reserved_size

                    # Adjust the user's quota
                    dynamodb.update_item(
                        TableName=USERS_TABLE,
                        Key={"userId": {"S": user_id}},
                        UpdateExpression="ADD usedBytes :diff",
                        ExpressionAttributeValues={
                            ":diff": {"N": str(diff)}
                        }
                    )

            except Exception as e:
                print(f"ERROR: S3 HEAD failed for {key}: {e}")
                # Mark file as CORRUPT if metadata exists
                mark_corrupt(file_id, user_id, str(e))
                continue

            # ---------------------------------------------------
            # 2. Update DynamoDB metadata entry
            # ---------------------------------------------------
            try:
                dynamodb.update_item(
                    TableName=TABLE,
                    Key={
                        "fileId": {"S": file_id},
                        "userId": {"S": user_id}
                    },
                    UpdateExpression="""
                        SET #s = :active,
                            checksum = :checksum,
                            sizeBytes = :size
                    """,
                    ExpressionAttributeNames={
                        "#s": "status"
                    },
                    ExpressionAttributeValues={
                        ":active": {"S": "ACTIVE"},
                        ":checksum": {"S": etag},
                        ":size": {"N": str(actual_size)}
                    }
                )
                print(f"Metadata updated for file {file_id}")

            except Exception as e:
                print(f"ERROR updating DynamoDB: {e}")
                traceback.print_exc()
                mark_corrupt(file_id, user_id, "Metadata update failed")

        return {"status": "ok"}

    except Exception as e:
        print("FATAL ERROR in lambda:")
        print(e)
        traceback.print_exc()
        return {"status": "error", "details": str(e)}


def mark_corrupt(file_id, user_id, reason):
    """
    Marks an item as CORRUPT if something went wrong
    (failed upload, S3 HEAD failure, metadata update fail, etc.)
    """
    try:
        dynamodb.update_item(
            TableName=TABLE,
            Key={
                "fileId": {"S": file_id},
                "userId": {"S": user_id}
            },
            UpdateExpression="SET #s = :corrupt, errorDetail = :reason",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":corrupt": {"S": "CORRUPT"},
                ":reason": {"S": reason}
            }
        )
        print(f"Marked file {file_id} as CORRUPT: {reason}")

    except Exception as e:
        print(f"Failed to mark CORRUPT: {e}")
