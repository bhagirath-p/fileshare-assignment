output "primary_bucket" {
  value = aws_s3_bucket.primary.bucket
}

output "secondary_bucket" {
  value = aws_s3_bucket.secondary.bucket
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "api_invoke_url" {
  value = "${aws_api_gateway_rest_api.api.execution_arn}/prod"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.metadata.name
}

output "presign_lambda_primary_arn" {
  value = aws_lambda_function.presign_primary.arn
}

output "presign_lambda_secondary_arn" {
  value = aws_lambda_function.presign_secondary.arn
}
