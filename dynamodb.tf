resource "aws_dynamodb_table" "metadata" {
  provider = aws.primary
  name     = local.dynamodb_table_name

  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fileId"
  range_key    = "userId"

  attribute {
    name = "fileId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name               = "user_createdAt_index"
    hash_key           = "userId"
    range_key          = "createdAt"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  # 🔥 The correct way to add a DR replica region
  replica {
    region_name = var.secondary_region
  }

  tags = var.tags
}

resource "aws_dynamodb_table" "shares" {
  name         = "shares"
  billing_mode = "PAY_PER_REQUEST"

  # Primary key: Who the item is shared with
  hash_key  = "targetUserId"
  range_key = "fileId"

  attribute {
    name = "targetUserId"
    type = "S"
  }

  attribute {
    name = "fileId"
    type = "S"
  }

  # attribute {
  #   name = "ownerUserId"
  #   type = "S"
  # }
  #
  # attribute {
  #   name = "sharedAt"
  #   type = "N"
  # }

  # GSI for download validator
  global_secondary_index {
    name               = "targetUserId_fileId_index"
    hash_key           = "targetUserId"
    range_key          = "fileId"
    projection_type    = "ALL"
  }
}

resource "aws_dynamodb_table" "users" {
  name         = "users"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  # attribute {
  #   name = "usedBytes"
  #   type = "N"
  # }
}

