############################
# 1. Frontend S3 Bucket
############################

resource "aws_s3_bucket" "frontend" {
  bucket = "file-sharing-frontend-eg-eu-west-1"

  tags = {
    Name = "frontend-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_block" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend_versioning" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}


############################
# 2. CloudFront Origin Access Control (OAC)
############################

resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                  = "frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior      = "always"
  signing_protocol      = "sigv4"
}


############################
# 3. S3 Bucket Policy for CloudFront
############################

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" : aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}


############################
# 4. CloudFront Distribution
############################

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  comment             = "React Frontend Hosting"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "frontend-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


############################
# 5. Output the CloudFront URL
############################

output "frontend_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}
