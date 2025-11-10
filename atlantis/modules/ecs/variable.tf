variable "cluster_name" {
  type = string
}
variable "capacity_providers" {
  type = list(string)
}
variable "base" {
  type = number
}
variable "weight" {
  type = number
}
variable "capacity_provider" {
  type = string
}
variable "ecs_service_name" {
  type = string
}
variable "desired_count_service" {
  type = string
}
variable "launch_type" {
  type = string
}
variable "private_subnets" {
  type = list(string)
}
variable "assign_public_ip" {
  type = bool
}
variable "container_name" {
  type = string
}
variable "container_port" {
  type = number
}
variable "backend_target_group_arn" {
  type = string
}
variable "backend_task_family" {
  type = string
}
variable "network_mode" {
  type = string
}
variable "requires_compatibilities" {
  type = list(string)
}
variable "cpu" {
  type = number
}
variable "memory" {
  type = number
}
variable "operating_system_family" {
  type = string
}
variable "cpu_architecture" {
  type = string
}
variable "container_cpu" {
  type = number
}
variable "container_memory" {
  type = number
}
variable "container_essential" {
  type = bool
}
variable "command" {
  type = list(string)
}
variable "containerPort" {
  type = number
}
variable "hostPort" {
  type = number
}
variable "log_driver" {
  type = string
}
variable "log_stream_prefix" {
  type = string
}
variable "backend_cloudwatch_group_name" {
  type = string
}
variable "log_retention" {
  type = number
}
variable "backend_service_sg" {
  type = string
}
variable "backend_sg_description" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "protocol" {
  type = string
}
variable "from_port" {
  type = number
}
variable "to_port" {
  type = number
}
variable "cidr_blocks" {
  type = list(string)
}
variable "backend_task_role_name" {
  type = string
}
variable "backend_execution_role_name" {
  type = string
}
variable "region" {
  type = string
}
variable "gh_app_key" {
  type = string
}
variable "image" {
  type = string
}
variable "repo_config_file" {
  type = string
}
variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "List of all environment variables for the Atlantis container"
}
variable "atlantis_url" {
  type        = string
}

variable "repo_config_json" {
  type        = string
}

variable "gh_app_id" {
  type        = string
}
variable "github_webhook_secret" {
  type        = string
}