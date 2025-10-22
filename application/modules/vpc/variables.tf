variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "vpc_name" {
  type        = string
  description = "Name of the VPC"
}

variable "internet_gateway" {
  type        = string
  description = "Name of the internet gateway"
}

variable "public_subnet_cidr" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
}

variable "private_subnet_cidr" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
}

variable "public_availability_zones" {
  type        = list(string)
  description = "Availability zones for public subnets"
}

variable "private_availability_zones" {
  type        = list(string)
  description = "Availability zones for private subnets"
}

variable "public_subnet_name" {
  type        = list(string)
  description = "Names for public subnets"
}

variable "private_subnet_name" {
  type        = list(string)
  description = "Names for private subnets"
}

variable "cidr_block" {
  type        = string
  description = "CIDR block for route destination (e.g., 0.0.0.0/0)"
}

variable "nat_gateway" {
  type        = string
  description = "Name of the NAT Gateway"
}

variable "route_table_public" {
  type        = string
  description = "Name of the public route table"
}

variable "route_table_private" {
  type        = string
  description = "Name of the private route table"
}

variable "eip_name" {
  type        = string
 
}