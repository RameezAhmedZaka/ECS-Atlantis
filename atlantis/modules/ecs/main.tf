
resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name = aws_ecs_cluster.cluster.name

  capacity_providers = var.capacity_providers

  default_capacity_provider_strategy {
    base              = var.base
    weight            = var.weight
    capacity_provider = var.capacity_provider
  }
}

resource "aws_ecs_service" "atlantis_service" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  desired_count   = var.desired_count_service
  launch_type     = var.launch_type

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [aws_security_group.backend_service.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    container_name   = var.container_name
    container_port   = var.container_port
    target_group_arn = var.backend_target_group_arn
  }

}

resource "aws_ecs_task_definition" "backend_task" {
  family = var.backend_task_family

  network_mode             = var.network_mode
  requires_compatibilities = var.requires_compatibilities

  cpu    = var.cpu
  memory = var.memory

  runtime_platform {
    operating_system_family = var.operating_system_family
    cpu_architecture        = var.cpu_architecture
  }

  execution_role_arn = aws_iam_role.backend_execution_role.arn
  task_role_arn      = aws_iam_role.backend_task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = "ghcr.io/runatlantis/atlantis:latest"
      cpu       = var.container_cpu
      memory    = var.container_memory
      essential = var.container_essential
      command   = var.command

      portMappings = [
        {
          name          = var.container_name
          containerPort = var.containerPort
          hostPort      = var.hostPort
        }
      ]

      environment = [
        {
          name  = "ATLANTIS_PORT"
          value = var.atlantis_port
        },
        {
          name  = "ATLANTIS_ATLANTIS_URL"
          value = var.atlantis_url
        },
        {
          name  = "ATLANTIS_REPO_ALLOWLIST"
          value = var.atlantis_repo_allowlist
        },
        {
          name  = "ATLANTIS_ENABLE_DIFF_MARKDOWN_FORMAT"
          value = var.atlantis_markdown_format
        },
        {
        name : "ATLANTIS_REPO_CONFIG_JSON",
        value : jsonencode(yamldecode(file("${path.module}/server-atlantis.yaml"))),
        },
        # {
        #   name  = "ATLANTIS_MAX_COMMENTS_PER_COMMAND"
        #   value = "1"  
        # },
        {
          name  = "ATLANTIS_GH_APP_ID"
          value = var.github_app_id
        }
      ]
      secrets = [
        {
          name      = "ATLANTIS_GH_APP_KEY"
          valueFrom = var.gh_app_key
        }
      ]

      logConfiguration = {
        logDriver = var.log_driver
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.log_stream_prefix
        }
      }
    }
  ])

  tags = {}
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = var.backend_cloudwatch_group_name
  retention_in_days = var.log_retention
}

resource "aws_security_group" "backend_service" {
  name        = var.backend_service_sg
  description = var.backend_sg_description
  vpc_id      = var.vpc_id

  ingress {
    protocol    = var.protocol
    from_port   = var.from_port
    to_port     = var.to_port
    cidr_blocks = var.cidr_blocks
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
data "aws_iam_policy_document" "ecs_assume_role_policy_doc" {
  version = "2012-10-17"

  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
    }
    sid = ""
  }
}

resource "aws_iam_role" "backend_task_role" {
  name               = var.backend_task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
}

# Attach full admin to Task Role
resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.backend_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "allow_all_secrets_manager_doc" {
  version = "2012-10-17"

  statement {
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:ListSecrets",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]
    effect    = "Allow"
    resources = ["*"]
    sid       = ""
  }
}

data "aws_iam_policy_document" "allow_api_gateway_execute" {
  version = "2012-10-17"

  statement {
    actions = [
      "execute-api:Invoke",
      "execute-api:ManageConnections"
    ]
    effect    = "Allow"
    resources = ["arn:aws:execute-api:${var.region}:*:*"]
  }
}

resource "aws_iam_policy" "secrets_manager_access" {
  name   = "SecretsManagerAccess"
  policy = data.aws_iam_policy_document.allow_all_secrets_manager_doc.json
}

resource "aws_iam_policy" "api_gateway_access" {
  name   = "APIGatewayExecute"
  policy = data.aws_iam_policy_document.allow_api_gateway_execute.json
}

resource "aws_iam_role" "backend_execution_role" {
  name               = var.backend_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "execution_role_attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  ])
  role       = aws_iam_role.backend_execution_role.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "attach_secrets_to_execution_role" {
  role       = aws_iam_role.backend_execution_role.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}
