# Primary S3 bucket
resource "aws_s3_bucket" "primary" {
  provider = aws
  bucket = "file-sharing-app-eg-ap-southeast-2"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "primary_ownership" {
  bucket = aws_s3_bucket.primary.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "primary_public_access_block" {
  bucket = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "primary_versioning" {
  bucket = aws_s3_bucket.primary.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 replication configuration
resource "aws_s3_bucket" "secondary" {
  provider = aws.replica
  bucket   = "file-sharing-app-eg-eu-west-1"
}

resource "aws_s3_bucket_versioning" "secondary_versioning" {
  provider = aws.replica
  bucket   = aws_s3_bucket.secondary.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "replication" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "s3.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "replication_policy" {
  name = "s3-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
        ],
        Effect   = "Allow",
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.secondary.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication_role_policy_attach" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication_policy.arn
}

resource "aws_s3_bucket_replication_configuration" "primary_replication" {
  bucket = aws_s3_bucket.primary.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.secondary.arn
      storage_class = "STANDARD"
    }
  }
}

# S3 Notification for file uploads (Lambda trigger)
resource "aws_s3_bucket_notification" "primary_upload_notifications" {
  bucket = aws_s3_bucket.primary.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_s3_invoke_file_processor
  ]
}

# NEW CloudFront OAC Bucket Policy (Added for you)
resource "aws_s3_bucket_policy" "primary_policy" {
  bucket = aws_s3_bucket.primary.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowCloudFrontOACRead",
        Effect    = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action    = ["s3:GetObject"],
        Resource  = "${aws_s3_bucket.primary.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}
