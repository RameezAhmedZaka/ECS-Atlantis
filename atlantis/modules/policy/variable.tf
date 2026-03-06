variable "policy_name" {
  type = string
}
variable "path" {
  type = string
}
variable "description" {
  type = string
}
variable "terraform_role_name" {
  type        = string
  description = "name of terraform role"
}
variable "environment" {
  type        = string
  description = "The environment for the role (e.g., production, staging)"
}