data "aws_availability_zones" "all" {}

locals {
  repo_config_json = jsonencode(yamldecode(file(var.atlantis_ecs.repo_config_file)))
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name                 = var.vpc.vpc_name
  cidr                 = var.vpc.cide_block
  azs                  = data.aws_availability_zones.all.names
  public_subnets       = var.vpc.public_subnets
  private_subnets      = var.vpc.private_subnets
  single_nat_gateway   = true
  enable_nat_gateway   = var.vpc.enable_nat_gateway
  enable_dns_hostnames = var.vpc.enable_dns_hostnames
  enable_dns_support   = var.vpc.enable_dns_support
}

module "backend" {
  source                        = "./modules/ecs"
  cluster_name                  = var.atlantis_ecs.cluster_name
  capacity_providers            = var.atlantis_ecs.capacity_providers
  base                          = var.atlantis_ecs.base
  weight                        = var.atlantis_ecs.weight
  capacity_provider             = var.atlantis_ecs.capacity_provider
  ecs_service_name              = var.atlantis_ecs.ecs_service_name
  desired_count_service         = var.atlantis_ecs.desired_count_service
  launch_type                   = var.atlantis_ecs.launch_type
  private_subnets               = module.vpc.private_subnets
  assign_public_ip              = var.atlantis_ecs.assign_public_ip
  container_name                = var.atlantis_ecs.container_name
  container_port                = var.atlantis_ecs.container_port
  backend_target_group_arn      = module.lb.target_group_arn
  backend_task_family           = var.atlantis_ecs.backend_task_family
  network_mode                  = var.atlantis_ecs.network_mode
  requires_compatibilities      = var.atlantis_ecs.requires_compatibilities
  cpu                           = var.atlantis_ecs.cpu
  memory                        = var.atlantis_ecs.memory
  operating_system_family       = var.atlantis_ecs.operating_system_family
  cpu_architecture              = var.atlantis_ecs.cpu_architecture
  container_cpu                 = var.atlantis_ecs.container_cpu
  container_memory              = var.atlantis_ecs.container_memory
  container_essential           = var.atlantis_ecs.container_essential
  command                       = var.atlantis_ecs.command
  containerPort                 = var.atlantis_ecs.containerPort
  hostPort                      = var.atlantis_ecs.hostPort
  log_driver                    = var.atlantis_ecs.log_driver
  region                        = var.atlantis_ecs.region
  log_stream_prefix             = var.atlantis_ecs.log_stream_prefix
  backend_cloudwatch_group_name = var.atlantis_ecs.backend_cloudwatch_group_name
  log_retention                 = var.atlantis_ecs.log_retention
  backend_service_sg            = var.atlantis_ecs.backend_service_sg
  backend_sg_description        = var.atlantis_ecs.backend_sg_description
  vpc_id                        = module.vpc.vpc_id
  protocol                      = var.atlantis_ecs.protocol
  from_port                     = var.atlantis_ecs.from_port
  to_port                       = var.atlantis_ecs.to_port
  cidr_blocks                   = var.atlantis_ecs.cidr_blocks
  backend_task_role_name        = var.atlantis_ecs.backend_task_role_name
  backend_execution_role_name   = var.atlantis_ecs.backend_execution_role_name
  gh_app_key                    = module.github_webhook.gh_app_key
  image                         = var.atlantis_ecs.image
  repo_config_file              = var.atlantis_ecs.repo_config_file
  environment_variables         = var.atlantis_ecs.environment_variables
  atlantis_url                  = module.apigateway.atlantis_url_gui
  gh_app_id                     = var.github_repositories_webhook.github_app_id
  repo_config_json              = local.repo_config_json
  github_webhook_secret         = var.atlantis_ecs.github_webhook_secret
}

module "github_webhook" {
  source                     = "./modules/github-repository-webhook"
  github_app_key_base64      = var.github_repositories_webhook.github_app_key_base64
  github_app_pem_file        = var.github_repositories_webhook.github_app_pem_file
  github_owner               = var.github_repositories_webhook.github_owner
  create                     = var.github_repositories_webhook.create
  repositories               = var.github_repositories_webhook.repositories
  webhook_url                = module.apigateway.atlantis_url_webhook
  content_type               = var.github_repositories_webhook.insecure_ssl
  insecure_ssl               = var.github_repositories_webhook.insecure_ssl
  events                     = var.github_repositories_webhook.events
  github_app_id              = var.github_repositories_webhook.github_app_id
  github_app_installation_id = var.github_repositories_webhook.github_app_installation_id

}

module "lb" {
  source             = "./modules/lb"
  lb_name            = var.lb.lb_name
  internal           = var.lb.internal
  load_balancer_type = var.lb.load_balancer_type
  public_subnets     = module.vpc.public_subnets
  target_group_name  = var.lb.target_group_name
  port               = var.lb.port
  protocol           = var.lb.protocol
  vpc_id             = module.vpc.vpc_id
  target_type        = var.lb.target_type
  listener_port      = var.lb.listener_port
  listener_protocol  = var.lb.listener_protocol
  lb_sg_name         = var.lb.lb_sg_name
}


module "apigateway" {
  source                   = "./modules/apigateway"
  vpc_link                 = var.atlantis_api_gateway.vpc_link
  vpc_id                   = module.vpc.vpc_id
  private_subnets          = module.vpc.private_subnets
  integration_type         = var.atlantis_api_gateway.integration_type
  integration_method       = var.atlantis_api_gateway.integration_method
  connection_type          = var.atlantis_api_gateway.connection_type
  payload_format_version   = var.atlantis_api_gateway.payload_format_version
  request_parameters       = var.atlantis_api_gateway.request_parameters
  atlantis_gui_route_key   = var.atlantis_api_gateway.atlantis_gui_route_key
  atlantis_proxy_route_key = var.atlantis_api_gateway.atlantis_proxy_route_key
  atlantis_sg_name         = var.atlantis_api_gateway.atlantis_sg_name
  atlantis_sg_description  = var.atlantis_api_gateway.atlantis_sg_description
  from_port                = var.atlantis_api_gateway.from_port
  to_port                  = var.atlantis_api_gateway.to_port
  protocol                 = var.atlantis_api_gateway.protocol
  cidr_blocks              = var.atlantis_api_gateway.cidr_blocks
  lb_listener_arn          = module.lb.lb_listener_arn
  api_name                 = var.atlantis_api_gateway.api_name
}
