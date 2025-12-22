module "my_bucket" {
  source      = "./modules/s3"
  bucket_name = var.bucket_name
  environment = var.environment
}

module "vpc" {
  source             = "./modules/vpc"
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones = var.availability_zones
}
