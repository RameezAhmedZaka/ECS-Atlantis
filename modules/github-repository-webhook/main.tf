data "aws_ssm_parameter" "github_app_key_base64" {
  name = var.github_app_key_base64
}
data "aws_ssm_parameter" "github_app_pem_file" {
  name = var.github_app_pem_file
}
provider "github" {
  owner = var.github_owner
  app_auth {
    id              = var.github_app_id
    pem_file        = base64decode(data.aws_ssm_parameter.github_app_key_base64.value)
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
    secret       = var.webhook_secret
  }
  events = var.events
}