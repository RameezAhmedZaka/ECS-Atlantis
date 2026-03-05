provider "aws" {
  assume_role {
    role_arn = var.assume_role_arn
  }
  region = var.region
}
