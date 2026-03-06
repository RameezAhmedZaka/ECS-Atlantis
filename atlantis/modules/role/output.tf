
output "terraform_role" {
  value = contains(["production", "stage"], var.environment) ? aws_iam_role.terraform_role: null
  description = "The IAM role created for Terraform (only for production and stage environments)"
}


