variable "environment" {
  description = "Environment name (staging, prod, helia)"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "region" {
  description = "AWS region to create S3 bucket in"
  type        = string
}