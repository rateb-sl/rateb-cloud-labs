locals {
  website_origin_id = "s3-website-origin"
}

resource "random_string" "bucket_suffix" {
  length  = 12
  special = false
  upper   = false
}

resource "aws_s3_bucket" "website" {
  bucket = "${var.project_name}-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }
}

# A public S3 website endpoint requires bucket-level public access blocking
# to be disabled. The bucket policy below grants only anonymous object reads.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = var.index_document
  source       = "${path.module}/site/${var.index_document}"
  content_type = "text/html"
  etag         = filemd5("${path.module}/site/${var.index_document}")
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.website.id
  key          = var.error_document
  source       = "${path.module}/site/${var.error_document}"
  content_type = "text/html"
  etag         = filemd5("${path.module}/site/${var.error_document}")
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  default_root_object = var.index_document
  price_class         = "PriceClass_100"
  wait_for_deployment = true

  origin {
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = local.website_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.website_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/${var.error_document}"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket_policy.website,
    aws_s3_object.index,
    aws_s3_object.error
  ]
}
