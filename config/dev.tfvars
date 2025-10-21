aws = {
  region  = "us-east-1"
  profile = "admin"
}

vpc = {
  vpc_name             = "atlantis"
  cide_block           = "10.75.0.0/16"
  public_subnets       = ["10.75.0.0/20", "10.75.16.0/20", "10.75.32.0/20"]
  private_subnets      = ["10.75.112.0/20", "10.75.128.0/20"]
  enable_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

atlantis_ecs = {
  cluster_name                  = "atlantis"
  capacity_providers            = ["FARGATE"]
  base                          = 1
  weight                        = 100
  capacity_provider             = "FARGATE"
  ecs_service_name              = "atlantis"
  desired_count_service         = 1
  launch_type                   = "FARGATE"
  assign_public_ip              = false
  container_name                = "atlantis"
  container_port                = 4141
  backend_task_family           = "atlantis"
  network_mode                  = "awsvpc"
  requires_compatibilities      = ["FARGATE"]
  cpu                           = 512
  memory                        = 1024
  operating_system_family       = "LINUX"
  cpu_architecture              = "X86_64"
  container_cpu                 = 512
  container_memory              = 1024
  container_essential           = true
  command                       = ["server", "--write-git-creds"]
  containerPort                 = 4141
  hostPort                      = 4141
  atlantis_port                 = 4141
  atlantis_repo_allowlist       = "github.com/organization-name/*" #specify repo to allowlist
  atlantis_markdown_format      = "true"
  log_driver                    = "awslogs"
  log_stream_prefix             = "ecs"
  backend_cloudwatch_group_name = "/aws/ecs/atlantis"
  log_retention                 = 7
  backend_service_sg            = "atlantis-sg"
  backend_sg_description        = "Atlantis ECS security Group"
  protocol                      = "tcp"
  from_port                     = 4141
  to_port                       = 4141
  cidr_blocks                   = ["10.75.0.0/16"]
  backend_task_role_name        = "atlantis-task-role"
  backend_execution_role_name   = "atlantis-execution-role"
  region                        = "us-east-1"
}

github_repositories_webhook = {
  github_owner               = "owner-of-gihub-app" 
  github_app_key_base64      = "github_app_key_base64" #base64 pemfile
  github_app_pem_file        = "github_app_key_plain" #pem-file-as-it-is
  create                     = true
  repositories               = ["terraform"] # repositories to add webhook to
  webhook_secret             = "test"
  insecure_ssl               = false
  content_type               = "application/json"
  events                     = ["issue_comment", "pull_request", "pull_request_review", "pull_request_review_comment"]
  github_app_id              = "github-app-id"
  github_app_installation_id = "github-installation-id"
}

lb = {
  lb_name            = "atlantis-nlb"
  internal           = true
  load_balancer_type = "network"
  target_group_name  = "atlantis-tg"
  port               = 4141
  protocol           = "TCP"
  target_type        = "ip"
  listener_port      = 80
  listener_protocol  = "TCP"
  lb_sg_name         = "atlantis-alb-sg"
}

atlantis_api_gateway = {
  vpc_link               = "atlantis-vpc-link-http"
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  payload_format_version = "1.0"
  request_parameters = {
    "append:header.x-forwarded-prefix" = "/atlantis"
    "overwrite:path"                   = "/$request.path.proxy"
  }
  atlantis_gui_route_key   = "ANY /atlantis"
  atlantis_proxy_route_key = "ANY /atlantis/{proxy+}"
  atlantis_sg_name         = "atlantis-api-gw-sg"
  atlantis_sg_description  = "Allow API Gateway to reach Atlantis NLB"
  from_port                = 4141
  to_port                  = 4141
  protocol                 = "tcp"
  cidr_blocks              = ["0.0.0.0/0"]
  api_id                   = "v0iztfg8vl"
}