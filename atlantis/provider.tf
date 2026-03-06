provider "aws" {
  region = "us-east-1"
  # profile = "atsstage"

  default_tags {
    tags = {
      environment = var.base.environment
      project     = var.base.project
      deployment  = "deployed with terraform"
      "cost-allocation:ApplicationId"  = "console"
      "cost-allocation:ComponentId"    = "enrolment" # to be clarified
      "cost-allocation:BusinessUnitId" = "procurement"
      "operations:Owner"               = "sre"
      "automation:EnvironmentId"       = var.base.environment
      "automation:DeploymentMethod"    = "terraform"
      "automation:DeploymentRepo"       = "infra"
      "automation:DeploymentName"       = "CICD/atlantis"
    }
  }
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}