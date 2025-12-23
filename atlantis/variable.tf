variable "atlantis_secret" {
  type = string
}

variable "aws" {
  type = object({
    region  = string
    profile = string
  })
}

variable "vpc" {
  type = object({
    vpc_name             = string
    cidr_block           = string
    public_subnets       = list(string)
    private_subnets      = list(string)
    enable_nat_gateway   = bool
    enable_dns_hostnames = bool
    enable_dns_support   = bool
  })
}
variable "atlantis_ecs" {
  type = object({
    cluster_name                  = string
    capacity_providers            = list(string)
    base                          = number
    weight                        = number
    capacity_provider             = string
    ecs_service_name              = string
    desired_count_service         = number
    launch_type                   = string
    assign_public_ip              = bool
    container_name                = string
    container_port                = number
    backend_task_family           = string
    network_mode                  = string
    requires_compatibilities      = list(string)
    cpu                           = number
    memory                        = number
    operating_system_family       = string
    cpu_architecture              = string
    container_cpu                 = number
    container_memory              = number
    container_essential           = bool
    command                       = list(string)
    containerPort                 = number
    hostPort                      = number
    log_driver                    = string
    log_stream_prefix             = string
    backend_cloudwatch_group_name = string
    log_retention                 = number
    backend_service_sg            = string
    backend_sg_description        = string
    protocol                      = string
    from_port                     = number
    to_port                       = number
    cidr_blocks                   = list(string)
    backend_task_role_name        = string
    backend_execution_role_name   = string
    region                        = string
    image                         = string
    # github_app_secret_arn         = string
    repo_config_file              = string
    environment_variables         = list(object({
      name  = string
      value = string
    }))
  })
}
variable "github_repositories_webhook" {
  type = object({
    github_owner               = string
    github_app_id              = string
    github_app_installation_id = string
    create                     = bool
    repositories               = list(string)
    insecure_ssl               = bool
    content_type               = string
    events                     = list(string)
  })
}
variable "lb" {
  type = object({
    lb_name            = string
    internal           = bool
    load_balancer_type = string
    target_group_name  = string
    port               = number
    protocol           = string
    target_type        = string
    listener_port      = number
    listener_protocol  = string
    lb_sg_name         = string
  })
}
variable "atlantis_api_gateway" {
  type = object({
    vpc_link                 = string
    integration_type         = string
    integration_method       = string
    connection_type          = string
    payload_format_version   = string
    request_parameters       = map(string)
    atlantis_gui_route_key   = string
    atlantis_proxy_route_key = string
    atlantis_sg_name         = string
    atlantis_sg_description  = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = list(string)
    api_name                 = string
  })
}
