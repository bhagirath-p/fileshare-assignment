# Build zip from lambda/ folder
data "archive_file" "presign_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/presign_lambda.zip"
}

# Lambda in primary region
resource "aws_lambda_function" "presign_primary" {
  provider = aws.primary
  filename         = data.archive_file.presign_zip.output_path
  function_name    = local.presign_lambda_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "presign_lambda.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  source_code_hash = data.archive_file.presign_zip.output_base64sha256

  environment {
    variables = {
      BUCKET = aws_s3_bucket.primary.bucket
      TABLE  = aws_dynamodb_table.metadata.name
      REGION = var.primary_region
      USERS_TABLE = aws_dynamodb_table.users.name
    }
  }

  depends_on = [aws_iam_role_policy.lambda_s3_dynamo_api]

  tags = var.tags
}

resource "aws_lambda_function" "file_processor" {
  function_name = "file-processor"
  handler       = "file_processor_lambda.lambda_handler"
  runtime       = "python3.12"

  filename         = "${path.module}/lambda/file_processor_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/file_processor_lambda.zip")

  role = aws_iam_role.file_processor_role.arn

  environment {
    variables = {
      TABLE = aws_dynamodb_table.metadata.name
    }
  }
}

resource "aws_iam_role" "file_processor_role" {
  name = "file-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "file_processor_policy" {
  name        = "file-processor-policy"
  description = "Allow Lambda to read S3 objects and update DynamoDB metadata"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:HeadObject"
        ]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.metadata.arn
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

resource "aws_iam_role_policy_attachment" "attach_file_processor_policy" {
  role       = aws_iam_role.file_processor_role.name
  policy_arn = aws_iam_policy.file_processor_policy.arn
}

resource "aws_lambda_function" "create_download" {
  function_name = "create-download"
  handler       = "create_download_lambda.lambda_handler"
  runtime       = "python3.12"

  filename         = "${path.module}/lambda/create_download_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/create_download_lambda.zip")

  role = aws_iam_role.create_download_role.arn

  environment {
    variables = {
      TABLE        = aws_dynamodb_table.metadata.name
      BUCKET       = aws_s3_bucket.primary.bucket
      SHARES_TABLE = aws_dynamodb_table.shares.name
      CF_DOMAIN      = aws_cloudfront_distribution.cdn.domain_name
      CF_KEY_PAIR_ID = aws_cloudfront_public_key.cdn_public_key.id
      CF_PRIVATE_KEY = file("${path.module}/cloudfront/private_key.pem")
    }
  }
}

# Lambda in secondary region (deploy same code)
resource "aws_lambda_function" "presign_secondary" {
  provider = aws.secondary
  filename         = data.archive_file.presign_zip.output_path
  function_name    = "${local.presign_lambda_name}-replica"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "presign_lambda.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  source_code_hash = data.archive_file.presign_zip.output_base64sha256

  environment {
    variables = {
      BUCKET = aws_s3_bucket.secondary.bucket
      TABLE  = aws_dynamodb_table.metadata.name
      REGION = var.secondary_region
    }
  }

  depends_on = [aws_iam_role_policy.lambda_s3_dynamo_api]

  tags = var.tags
}

resource "aws_lambda_function" "share" {
  function_name = "share-file"
  handler       = "share_lambda.lambda_handler"
  runtime       = "python3.12"

  filename         = "${path.module}/lambda/share_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/share_lambda.zip")

  role = aws_iam_role.share_role.arn

  environment {
    variables = {
      TABLE        = aws_dynamodb_table.metadata.name
      SHARES_TABLE = aws_dynamodb_table.shares.name
    }
  }
}

resource "aws_lambda_function" "list_shared" {
  function_name = "list-shared-with-me"
  handler       = "list_shared_lambda.lambda_handler"
  runtime       = "python3.12"

  filename         = "${path.module}/lambda/list_shared_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/list_shared_lambda.zip")

  role = aws_iam_role.list_shared_role.arn

  environment {
    variables = {
      SHARES_TABLE   = aws_dynamodb_table.shares.name
      METADATA_TABLE = aws_dynamodb_table.metadata.name
    }
  }
}

resource "aws_lambda_permission" "allow_s3_invoke_file_processor" {
  statement_id  = "AllowS3InvokeFileProcessor"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.primary.arn
}
