variable "atlantis_secret" {
  type    = string
  default = ""
}

variable "vpc" {
  type = object({
    vpc_name             = optional(string)
    cidr_block           = optional(string)
    public_subnets       = optional(list(string))
    private_subnets      = optional(list(string))
    enable_nat_gateway   = optional(bool)
    enable_dns_hostnames = optional(bool)
    enable_dns_support   = optional(bool)
  })
  default = {}
}

variable "atlantis_ecs" {
  type = object({
    cluster_name                  = optional(string)
    capacity_providers            = optional(list(string))
    base                          = optional(number)
    weight                        = optional(number)
    capacity_provider             = optional(string)
    ecs_service_name              = optional(string)
    desired_count_service         = optional(number)
    launch_type                   = optional(string)
    assign_public_ip              = optional(bool)
    container_name                = optional(string)
    container_port                = optional(number)
    backend_task_family           = optional(string)
    network_mode                  = optional(string)
    requires_compatibilities      = optional(list(string))
    cpu                           = optional(number)
    memory                        = optional(number)
    operating_system_family       = optional(string)
    cpu_architecture              = optional(string)
    container_cpu                 = optional(number)
    container_memory              = optional(number)
    container_essential           = optional(bool)
    command                       = optional(list(string))
    containerPort                 = optional(number)
    hostPort                      = optional(number)
    log_driver                    = optional(string)
    log_stream_prefix             = optional(string)
    backend_cloudwatch_group_name = optional(string)
    log_retention                 = optional(number)
    backend_service_sg            = optional(string)
    backend_sg_description        = optional(string)
    protocol                      = optional(string)
    from_port                     = optional(number)
    to_port                       = optional(number)
    cidr_blocks                   = optional(list(string))
    backend_task_role_name        = optional(string)
    backend_execution_role_name   = optional(string)
    region                        = optional(string)
    image                         = optional(string)
    repo_config_file              = optional(string)
    environment_variables         = optional(list(object({
      name  = optional(string)
      value = optional(string)
    })))
  })
  default = {}
}
variable "github_repositories_webhook" {
  type = object({
    github_owner               = optional(string)
    github_app_id              = optional(string)
    github_app_installation_id = optional(string)
    create                     = optional(bool)
    repositories               = optional(list(string))
    insecure_ssl               = optional(bool)
    content_type               = optional(string)
    events                     = optional(list(string))
    atlantis_secret            = optional(string)
    enabled                    = optional(bool)
  })
  default = {}  # now allowed
}
variable "lb" {
  type = object({
    lb_name            = optional(string)
    internal           = optional(bool)
    load_balancer_type = optional(string)
    target_group_name  = optional(string)
    port               = optional(number)
    protocol           = optional(string)
    target_type        = optional(string)
    listener_port      = optional(number)
    listener_protocol  = optional(string)
    lb_sg_name         = optional(string)
  })
  default = {}
}

variable "atlantis_api_gateway" {
  type = object({
    vpc_link                 = optional(string)
    integration_type         = optional(string)
    integration_method       = optional(string)
    connection_type          = optional(string)
    payload_format_version   = optional(string)
    request_parameters       = optional(map(string))
    atlantis_gui_route_key   = optional(string)
    atlantis_proxy_route_key = optional(string)
    atlantis_sg_name         = optional(string)
    atlantis_sg_description  = optional(string)
    from_port                = optional(number)
    to_port                  = optional(number)
    protocol                 = optional(string)
    cidr_blocks              = optional(list(string))
    api_name                 = optional(string)
  })
  default = {}
}

variable "base" {
  type = object({
    project          = optional(string)
    environment      = optional(string)
    owner_team       = optional(string)
    prod_account_id  = optional(string)
    stage_account_id = optional(string)
    svc_account_id   = optional(string)
    svc_role_name    = optional(string)
  })
  default = {}
}

variable "role" {
  type = object({
    terraform_role_name = optional(string)
  })
  default = {}
}

variable "policy" {
  type = object({
    policy_name = optional(string)
    path        = optional(string)
    description = optional(string)
  })
  default = {}
}