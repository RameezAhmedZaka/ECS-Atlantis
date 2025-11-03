resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true  # ensures bucket deletes even if not empty

  tags = {
    Environment = var.environment
  }
}