provider "aws" {
  region  = "eu-west-1"

  default_tags {
    tags = {
      environment = var.base.environment
      project     = var.base.project
      deployment  = "deployed with terraform"
      "cost-allocation:ApplicationId"  = "apollo"
      "cost-allocation:ComponentId"    = "sourcing"
      "cost-allocation:BusinessUnitId" = "procurement"
      "operations:Owner"               = "procurement"
      "automation:EnvironmentId"       = "procurement"
      "automation:DeploymentMethod"    = "terraform"
      "automation:DeploymenName"       = "infra/applications/apollo-backend"
    }
  }
}

provider "aws" {
  region  = "eu-central-1"
  alias   = "replica"

  default_tags {

    tags = {
      environment = var.base.environment
      project     = var.base.project
      deployment  = "deployed with terraform"
      "cost-allocation:ApplicationId"  = "apollo"
      "cost-allocation:ComponentId"    = "apollo"
      "cost-allocation:BusinessUnitId" = "procurement"
      "automation:DeploymenName"       = "infra/applications/apollo-backend"
    }
  }
}