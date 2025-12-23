data "aws_secretsmanager_secret_version" "github_app" {
  secret_id = "/github/app/atlantis"
}

locals {
  github_app_secret = jsondecode(
    data.aws_secretsmanager_secret_version.github_app.secret_string
  )
}

provider "github" {
  owner = var.github_owner
  app_auth {
    id              = var.github_app_id
    pem_file        = base64decode(local.github_app_secret.key_base64)
    installation_id = var.github_app_installation_id
  }
}

resource "github_repository_webhook" "webhook" {
  count = var.create ? length(var.repositories) : 0

  repository = var.repositories[count.index]

  configuration {
    url          = var.webhook_url
    content_type = var.content_type
    insecure_ssl = var.insecure_ssl
  }
  events = var.events
}