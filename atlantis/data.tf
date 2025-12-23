data "aws_availability_zones" "all" {}

data "aws_secretsmanager_secret_version" "github_app" {
  secret_id = var.atlantis_secret
}

locals {
  repo_config_json = jsonencode(yamldecode(file(var.atlantis_ecs.repo_config_file)))
  github_app_secret = jsondecode(data.aws_secretsmanager_secret_version.github_app.secret_string)
}