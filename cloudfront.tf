############################################################
# REMOVE OLD OAI (NO LONGER USED)
############################################################
# (delete these blocks from your file)
#
# resource "aws_cloudfront_origin_access_identity" "oai" { ... }
# data "aws_iam_policy_document" "s3_cloudfront_policy" { ... }
#

############################################################
# PUBLIC KEY (already defined by your previous block)
############################################################

resource "aws_cloudfront_public_key" "cdn_public_key" {
  name        = "file-sharing-public-key"
  comment     = "Public key for CloudFront signed URLs"
  encoded_key = file("${path.module}/cloudfront/public_key.pem")
}

resource "aws_cloudfront_key_group" "cdn_key_group" {
  name = "file-sharing-key-group"

  items = [
    aws_cloudfront_public_key.cdn_public_key.id
  ]
}

############################################################
# ORIGIN ACCESS CONTROL (already defined)
############################################################
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "file-sharing-oac"
  description                       = "OAC for secure S3 access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

############################################################
# CLOUDFRONT DISTRIBUTION (NEW)
############################################################

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.primary.bucket_regional_domain_name
    origin_id   = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  comment             = "File Sharing CDN"
  default_root_object = ""

  origin {
    domain_name = aws_s3_bucket.primary.bucket_regional_domain_name
    origin_id   = "s3-file-origin"

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-file-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    trusted_key_groups = [
      aws_cloudfront_key_group.cdn_key_group.id
    ]

    compress = true
    min_ttl  = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # No geo restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

############################################################
# S3 BUCKET POLICY FOR OAC
############################################################

# resource "aws_s3_bucket_policy" "primary_policy" {
#   bucket = aws_s3_bucket.primary.id
#
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Sid: "AllowCloudFrontServicePrincipal",
#         Effect: "Allow",
#         Principal: {
#           Service: "cloudfront.amazonaws.com"
#         },
#         Action: ["s3:GetObject"],
#         Resource: "${aws_s3_bucket.primary.arn}/*",
#         Condition: {
#           StringEquals: {
#             "AWS:SourceArn": aws_cloudfront_distribution.cdn.arn
#           }
#         }
#       }
#     ]
#   })
# }
