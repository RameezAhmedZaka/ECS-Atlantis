# data "aws_secretsmanager_secret_version" "github_webhook_secret" {
#   secret_id = "/github/app/webhook_secret"
# }

# data "aws_secretsmanager_secret_version" "github_app_key_base64" {
#   secret_id = "/github/app/key_base64"
# }

# data "aws_secretsmanager_secret_version" "github_app_private_key" {
#   secret_id = "/github/app/private_key"
# }

# locals {
#   github_app_secret = {
#     webhook_secret = data.aws_secretsmanager_secret_version.github_webhook_secret.secret_string
#     key_base64     = data.aws_secretsmanager_secret_version.github_app_key_base64.secret_string
#     private_key    = data.aws_secretsmanager_secret_version.github_app_private_key.secret_string
#   }
# }
