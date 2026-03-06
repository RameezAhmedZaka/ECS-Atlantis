resource "github_repository_webhook" "webhook" {
  count = var.enabled && var.create ? length(var.repositories) : 0

  repository = var.repositories[count.index]

  configuration {
    url          = var.webhook_url
    content_type = var.content_type
    insecure_ssl = var.insecure_ssl
  }
  events = var.events
}