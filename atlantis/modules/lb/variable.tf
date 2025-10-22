variable "lb_name" {
  type = string
}
variable "internal" {
  type = bool
}
variable "load_balancer_type" {
  type = string
}
variable "target_group_name" {
  type = string
}
variable "port" {
  type = number
}
variable "protocol" {
  type = string
}
variable "target_type" {
  type = string
}
variable "listener_port" {
  type = number
}
variable "listener_protocol" {
  type = string
}
variable "public_subnets" {
  type = list(string)
}
variable "vpc_id" {
  type = string
}
variable "lb_sg_name" {
  type = string
}