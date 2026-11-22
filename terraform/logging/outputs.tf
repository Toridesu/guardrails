output "log_bucket_name" {
  value = aws_s3_bucket.logs.id
}

output "log_kms_key_arn" {
  value = aws_kms_key.logs.arn
}

output "trail_arn" {
  value = aws_cloudtrail.org.arn
}
