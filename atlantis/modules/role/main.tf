resource "aws_iam_role" "terraform_role" {
  name = "terraform-managed-${var.terraform_role_name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.svc_account_id}:root"
        # AWS = "arn:aws:iam::${var.svc_account_id}:role/${var.svc_role_name}"
      }
      Action = "sts:AssumeRole"
    }]
  })
}