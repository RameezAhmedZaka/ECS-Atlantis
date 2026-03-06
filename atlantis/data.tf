data "aws_availability_zones" "all" {}

data "aws_secretsmanager_secret_version" "github_app" {
  count     = var.atlantis_secret != null && var.atlantis_secret != "" ? 1 : 0
  secret_id = var.atlantis_secret
}

locals {
  repo_config_json = try(jsonencode(yamldecode(file(var.atlantis_ecs.repo_config_file))), "{}")
  github_app_secret = length(data.aws_secretsmanager_secret_version.github_app) > 0 ? jsondecode(data.aws_secretsmanager_secret_version.github_app[0].secret_string) : {}
}
provider "github" {
  owner = var.github_repositories_webhook.github_owner

  dynamic "app_auth" {
    for_each = (
      var.base.environment != "shared-services" &&
      var.github_repositories_webhook.github_app_id != null &&
      var.github_repositories_webhook.github_app_installation_id != null
    ) ? [1] : []

    content {
      id              = var.github_repositories_webhook.github_app_id
      installation_id = var.github_repositories_webhook.github_app_installation_id
      pem_file        = base64decode(try(local.github_app_secret.key_base64, ""))
    }
  }
}