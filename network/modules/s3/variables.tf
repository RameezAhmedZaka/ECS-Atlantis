variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket"
}

variable "environment" {
  type        = string
  description = "Environment tag for the bucket"
}
