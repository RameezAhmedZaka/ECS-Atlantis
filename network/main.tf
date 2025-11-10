module "my_bucket" {
  source      = "./modules/s3"
  bucket_name = var.bucket_name
  environment = var.environment
}

module "vpc" {
  source            = "./modules/vpc"
  vpc_name          = var.vpc_name
  environment       = var.environment
  cidr_block        = var.cidr_block
  public_subnets    = var.public_subnets
  private_subnets   = var.private_subnets
  enable_nat_gateway = var.enable_nat_gateway
}
