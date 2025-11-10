region      = "us-east-1"
environment = "production"
bucket_name = "network-prod-bucket4271113"

vpc_name         = "my-app-vpc-prod"
environment      = "prod"
cidr_block       = "10.2.0.0/16"
public_subnets   = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnets  = ["10.2.11.0/24", "10.2.12.0/24"]
enable_nat_gateway = true


