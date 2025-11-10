region      = "us-east-1"
environment = "helia"
bucket_name = "network-helia-bucket11375256"

vpc_name         = "my-app-vpc-staging"
environment      = "staging"
cidr_block       = "10.1.0.0/16"
public_subnets   = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnets  = ["10.1.11.0/24", "10.1.12.0/24"]
enable_nat_gateway = true
