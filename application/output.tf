# VPC Outputs
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

# Bastion Outputs
output "bastion_instance_id" {
  value = module.bastion.bastion_instance_id
}

output "bastion_public_ip" {
  value = module.bastion.bastion_public_ip
}

output "bastion_sg_id" {
  value = module.bastion.bastion_sg_id
}
