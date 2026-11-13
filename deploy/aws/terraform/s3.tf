resource "random_id" "suffix" {
  byte_length = 4
}
resource "aws_s3_bucket" "ingest" {
  bucket = "${var.name}-ingest-${random_id.suffix.hex}"
}
resource "aws_s3_bucket_versioning" "ingest" {
  bucket = aws_s3_bucket.ingest.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "ingest" {
  bucket = aws_s3_bucket.ingest.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.ingest_kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.ingest_kms_key_arn
    }
    bucket_key_enabled = var.ingest_kms_key_arn != null
  }
}
resource "aws_s3_bucket_public_access_block" "ingest" {
  bucket                  = aws_s3_bucket.ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "ingest" {
  bucket = aws_s3_bucket.ingest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.ingest.arn, "${aws_s3_bucket.ingest.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_s3_bucket_lifecycle_configuration" "ingest" {
  count  = var.noncurrent_version_expiration_days == null ? 0 : 1
  bucket = aws_s3_bucket.ingest.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter { prefix = "" }
    noncurrent_version_expiration { noncurrent_days = var.noncurrent_version_expiration_days }
  }
  depends_on = [aws_s3_bucket_versioning.ingest]
}
