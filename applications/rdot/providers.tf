provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=4.5.0"
    }
  }
}
