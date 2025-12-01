# REST API
resource "aws_api_gateway_rest_api" "api" {
  name = local.api_name
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_rest_api" "file_api" {
  name        = "file-sharing-api"
  description = "API for file sharing application"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                    = "cognito-authorizer"
  rest_api_id             = aws_api_gateway_rest_api.file_api.id
  identity_source         = "method.request.header.Authorization"
  type                    = "COGNITO_USER_POOLS"
  provider_arns           = [aws_cognito_user_pool.users.arn]
}


# /presign endpoint
resource "aws_api_gateway_resource" "presign" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "presign"
}

# resource "aws_api_gateway_method" "presign_method" {
#   rest_api_id   = aws_api_gateway_rest_api.file_api.id
#   resource_id   = aws_api_gateway_resource.presign.id
#   http_method   = "POST"
#   authorization = "COGNITO_USER_POOLS"
#   authorizer_id = aws_api_gateway_authorizer.cognito.id
# }

resource "aws_api_gateway_method" "post_presign" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.presign.id
  http_method   = "POST"
  authorization = "NONE" # replace later with Cognito authorizer
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.presign.id
  http_method = aws_api_gateway_method.post_presign.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.presign_primary.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presign_primary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Deployment (NO stage_name allowed anymore)
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
}

# Stage must now be separate
resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "prod"
}

resource "aws_api_gateway_resource" "download_resource" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id
  parent_id   = aws_api_gateway_rest_api.file_api.root_resource_id
  path_part   = "download"
}

resource "aws_api_gateway_method" "download_method" {
  rest_api_id   = aws_api_gateway_rest_api.file_api.id
  resource_id   = aws_api_gateway_resource.download_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "download_integration" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id
  resource_id = aws_api_gateway_resource.download_resource.id
  http_method = aws_api_gateway_method.download_method.http_method

  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_download.invoke_arn
  integration_http_method = "POST"
}

resource "aws_lambda_permission" "api_gw_invoke_create_download" {
  statement_id  = "AllowAPIGatewayInvokeDownload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_download.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.file_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "file_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id

  triggers = {
    redeploy = sha1(join("", [
      jsonencode(aws_api_gateway_method.download_method),
      jsonencode(aws_api_gateway_integration.download_integration)
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.download_integration
  ]
}

resource "aws_api_gateway_resource" "share_resource" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id
  parent_id   = aws_api_gateway_rest_api.file_api.root_resource_id
  path_part   = "share"
}

resource "aws_api_gateway_method" "share_method" {
  rest_api_id   = aws_api_gateway_rest_api.file_api.id
  resource_id   = aws_api_gateway_resource.share_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "share_integration" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id
  resource_id = aws_api_gateway_resource.share_resource.id
  http_method = aws_api_gateway_method.share_method.http_method
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.share.invoke_arn
  integration_http_method = "POST"
}

resource "aws_lambda_permission" "api_gw_invoke_share" {
  statement_id  = "AllowAPIGatewayInvokeShare"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.file_api.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "shared_with_me_resource" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id
  parent_id   = aws_api_gateway_rest_api.file_api.root_resource_id
  path_part   = "shared-with-me"
}

resource "aws_api_gateway_method" "shared_with_me_method" {
  rest_api_id   = aws_api_gateway_rest_api.file_api.id
  resource_id   = aws_api_gateway_resource.shared_with_me_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "shared_with_me_integration" {
  rest_api_id = aws_api_gateway_rest_api.file_api.id
  resource_id = aws_api_gateway_resource.shared_with_me_resource.id
  http_method = aws_api_gateway_method.shared_with_me_method.http_method
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.list_shared.invoke_arn
  integration_http_method = "POST"
}

resource "aws_lambda_permission" "api_gw_invoke_list_shared" {
  statement_id  = "AllowAPIGatewayInvokeListShared"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_shared.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.file_api.execution_arn}/*/*"
}
