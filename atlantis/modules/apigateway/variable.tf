variable "vpc_link" {
  type = string
}
variable "integration_type" {
  type = string
}
variable "integration_method" {
  type = string
}
variable "connection_type" {
  type = string
}
variable "payload_format_version" {
  type = string
}
variable "request_parameters" {
  type = map(string)
}
variable "atlantis_gui_route_key" {
  type = string
}
variable "atlantis_proxy_route_key" {
  type = string
}
variable "private_subnets" {
  type = list(string)
}
variable "lb_listener_arn" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "atlantis_sg_name" {
  type = string
}
variable "atlantis_sg_description" {
  type = string
}
variable "from_port" {
  type = number
}
variable "to_port" {
  type = number
}
variable "protocol" {
  type = string
}
variable "cidr_blocks" {
  type = list(string)
}
variable "api_name" {
  type = string
}