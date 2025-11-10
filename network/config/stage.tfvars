region      = "us-east-1"
environment = "staging"
bucket_name = "network-stage-bucket335745"

vpc_name         = "my-app-vpc-dev"
environment      = "dev"
cidr_block       = "10.0.0.0/16"
public_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets  = ["10.0.11.0/24", "10.0.12.0/24"]
enable_nat_gateway = true
