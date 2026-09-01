output "bucket_name" {
  description = "Name of the S3 website bucket."
  value       = aws_s3_bucket.website.bucket
}

output "s3_website_endpoint" {
  description = "HTTP S3 website endpoint used as the CloudFront origin."
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "cloudfront_domain_name" {
  description = "CloudFront generated hostname."
  value       = aws_cloudfront_distribution.website.domain_name
}

output "website_url" {
  description = "HTTPS URL for the deployed website."
  value       = "https://${aws_cloudfront_distribution.website.domain_name}/"
}
