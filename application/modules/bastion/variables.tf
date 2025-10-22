variable "vpc_id" {
  description = "The VPC ID where the bastion host will be deployed"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the bastion host instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID where the bastion host will be placed"
  type        = string
}

variable "bastion_sg_name" {
  description = "Name of the bastion security group"
  type        = string
  default     = "bastion-sg"
}

variable "bastion_sg_egress_cidr" {
  description = "CIDR blocks for bastion SG egress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "user_data_file" {
  description = "Path to the user data script for bastion host"
  type        = string
}

variable "bastion_name" {
  description = "Tag: Name for the bastion instance"
  type        = string
}

variable "bastion_role" {
  description = "Tag: Role for the bastion instance"
  type        = string
}

variable "bastion_cluster" {
  description = "Tag: Cluster name for the bastion instance"
  type        = string
}

variable "key_name" {
  type        = string
}
