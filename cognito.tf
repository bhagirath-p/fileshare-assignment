resource "aws_cognito_user_pool" "users" {
  name = "${var.name_prefix}-user-pool"
  auto_verified_attributes = ["email"]
  tags = var.tags
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.users.id
  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}
