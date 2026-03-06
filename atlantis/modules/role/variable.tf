variable "terraform_role_policies" {
  description = "Managed policy ARNs to attach to the Terraform role."
  type        = list(string)
  default     = []
}

variable "environment" {
  type        = string
  description = "Environment to deploy (stage, production, svc)"
}

variable "prod_account_id" {
  type        = string
  description = "AWS Account ID for production environment"
  default     = ""
}

variable "stage_account_id" {
  type        = string
  description = "AWS Account ID for staging environment"
  default     = ""
}

variable "svc_account_id" {
  type        = string
  description = "AWS Account ID for shared service environment"
  default     = ""
}

variable "terraform_role_name" {
  description = "Terraform role name per environment"
  type        = string
  default     = ""
}

variable "svc_role_name" {
  description = "Shared Service role name"
  type        = string
  default     = ""
}
