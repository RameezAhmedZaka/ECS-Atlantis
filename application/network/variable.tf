variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "profile" {
  description = "Profile"
  type        = string
}

variable "vpc" {
  description = "VPC configuration"
  type = object({
    vpc_cidr_block              = string
    vpc_name                    = string
    internet_gateway            = string
    public_subnet_cidr          = list(string)
    private_subnet_cidr         = list(string)
    public_availability_zones   = list(string)
    private_availability_zones  = list(string)
    public_subnet_name          = list(string)
    private_subnet_name         = list(string)
    route_destination           = string
    nat_gateway                 = string
    route_table_public          = string
    route_table_private         = string
    cidr_block                  = string
    eip_name                    = string
  })
}

variable "bastion" {
  description = "Bastion host configuration"
  type = object({
    ami_id                  = string
    instance_type           = string
    user_data_file          = string
    bastion_sg_name         = string
    bastion_sg_egress_cidr  = list(string)
    bastion_name            = string
    bastion_role            = string
    bastion_cluster         = string
    key_name                = string
  })
}
