variable "enabled" {
  type = bool
  default = true
}
variable "github_owner" {
  type = string
}
variable "create" {
  type = bool
}
variable "repositories" {
  type = list(string)
}
variable "webhook_url" {
  type = string
}
variable "content_type" {
  type = string
}
variable "insecure_ssl" {
  type = bool
}
variable "events" {
  type = list(string)
}
variable "github_app_id" {
  type = string
}
variable "github_app_installation_id" {
  type = string
}
variable "atlantis_secret" {
  type = string
}