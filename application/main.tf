# ------------------------------
# VPC Module
# ------------------------------
module "vpc" {
  source                     = "./modules/vpc"
  vpc_cidr_block             = var.vpc.vpc_cidr_block
  vpc_name                   = var.vpc.vpc_name
  internet_gateway           = var.vpc.internet_gateway
  public_subnet_cidr         = var.vpc.public_subnet_cidr
  private_subnet_cidr        = var.vpc.private_subnet_cidr
  public_availability_zones  = var.vpc.public_availability_zones
  private_availability_zones = var.vpc.private_availability_zones
  public_subnet_name         = var.vpc.public_subnet_name
  private_subnet_name        = var.vpc.private_subnet_name
  cidr_block                 = var.vpc.route_destination
  nat_gateway                = var.vpc.nat_gateway
  route_table_public         = var.vpc.route_table_public
  route_table_private        = var.vpc.route_table_private
  eip_name                   = var.vpc.eip_name
}

# ------------------------------
# Bastion Module
# ------------------------------
module "bastion" {
  source                  = "./modules/bastion"
  vpc_id                  = module.vpc.vpc_id
  public_subnet_id        = module.vpc.public_subnet_ids[0]  # pick first public subnet
  ami_id                  = var.bastion.ami_id
  instance_type           = var.bastion.instance_type
  user_data_file          = var.bastion.user_data_file
  bastion_sg_name         = var.bastion.bastion_sg_name
  bastion_sg_egress_cidr  = var.bastion.bastion_sg_egress_cidr
  bastion_name            = var.bastion.bastion_name
  bastion_role            = var.bastion.bastion_role
  bastion_cluster         = var.bastion.bastion_cluster
  key_name                = var.bastion.key_name
}
