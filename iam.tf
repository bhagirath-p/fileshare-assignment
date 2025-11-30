# IAM documents and roles

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_dynamo_api" {
  name = "${var.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Resource = [
          "arn:aws:s3:::${local.bucket_primary_name}",
          "arn:aws:s3:::${local.bucket_primary_name}/*",
          "arn:aws:s3:::${local.bucket_secondary_name}",
          "arn:aws:s3:::${local.bucket_secondary_name}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# S3 replication role for primary -> secondary
data "aws_iam_policy_document" "s3_replication_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "s3_replication_role" {
  name               = "${var.name_prefix}-s3-replication-role"
  assume_role_policy = data.aws_iam_policy_document.s3_replication_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "s3_replication_policy" {
  name = "${var.name_prefix}-s3-replication-policy"
  role = aws_iam_role.s3_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${local.bucket_primary_name}",
          "arn:aws:s3:::${local.bucket_primary_name}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:PutObject"
        ],
        Resource = [
          "arn:aws:s3:::${local.bucket_secondary_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "create_download_role" {
  name = "create-download-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "create_download_policy" {
  name        = "create-download-policy"
  description = "Allow Lambda to read DynamoDB metadata and S3 objects"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = [
          aws_dynamodb_table.metadata.arn,
          aws_dynamodb_table.shares.arn,
          "${aws_dynamodb_table.shares.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:HeadObject"
        ]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_create_download_policy" {
  role       = aws_iam_role.create_download_role.name
  policy_arn = aws_iam_policy.create_download_policy.arn
}

resource "aws_iam_role" "share_role" {
  name = "share-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "share_policy" {
  name        = "share-policy"
  description = "Allow sharing of files"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = [
          aws_dynamodb_table.metadata.arn,
          aws_dynamodb_table.shares.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_share_policy" {
  role       = aws_iam_role.share_role.name
  policy_arn = aws_iam_policy.share_policy.arn
}

resource "aws_iam_role" "list_shared_role" {
  name = "list-shared-with-me-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "list_shared_policy" {
  name        = "list-shared-with-me-policy"
  description = "Allow listing files shared with a user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = [
          aws_dynamodb_table.shares.arn,
          "${aws_dynamodb_table.shares.arn}/index/*",
          aws_dynamodb_table.metadata.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_list_shared_policy" {
  role       = aws_iam_role.list_shared_role.name
  policy_arn = aws_iam_policy.list_shared_policy.arn
}

