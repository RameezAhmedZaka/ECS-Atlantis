# Atlantis on AWS ECS with API Gateway

This Terraform project deploys Atlantis on **AWS ECS Fargate**, integrated with **GitHub** and exposed through **API Gateway** via a **VPC Link** and **internal Network Load Balancer**.

Atlantis enables GitOps-style workflows by automating `terraform plan` and `apply` actions based on pull request activity in GitHub.

---

## 📦 What’s Deployed

- **VPC**: With public/private subnets and NAT Gateway.
- **ECS Fargate Service**: Runs the Atlantis container.
- **Internal NLB**: For network traffic routing inside the VPC.
- **API Gateway (REST)**: Publicly exposes Atlantis at `/atlantis`.
- **Security Groups**: Control traffic between components.
- **GitHub Webhook**: Automatically created and linked to your repository.

---

## 🔑 GitHub Integration

Atlantis interacts with GitHub using:

1. **GitHub App**  
   Required to:
   - Clone repositories
   - Comment on pull requests
   - Access GitHub APIs

Your GitHub App must be configured with these permissions:

| Category            | Permission     |
|---------------------|----------------|
| Administration      | Read & write   |
| Checks              | Read & write   |
| Commit statuses     | Read & write   |
| Contents            | Read & write   |
| Issues              | Read & write   |
| Metadata            | Read-only      |
| Pull Requests       | Read & write   |
| Webhooks            | Read & write   |
| Members             | Read-only      |
| Actions             | Read-only      |

  **Subscribe to Events:**
  - `check_suite`
  - `check_run`
  - `issue_comment`
  - `pull_request`
  - `repository`


   Define the github app parameters in your `terraform.tfvars` file:

   ```hcl
    github_repositories_webhook = {
      github_owner               = "owner-of-gihub-app" 
      github_app_key_base64      = "github_app_key_base64" #base64 pemfile
      github_app_pem_file        = "github_app_key_plain" #pem-file-as-it-is
      repositories               = ["terraform"] # repositories to add webhook to
      github_app_id              = "github-app-id"
      github_app_installation_id = "github-installation-id"
    }

    To locate your github_app_installation_id:

    Go to your organization on GitHub.

    Navigate to Settings → Third-party Access → GitHub Apps.

    Click the Configure button for your GitHub App.

    In the URL, you'll see something like:
    https://github.com/organizations/organization-name/settings/installations/61773491
    The number at the end (61773491 in this example) is your GitHub App Installation ID.

Repository Allowlist
Atlantis will only respond to Terraform changes in repositories you allow:

atlantis_ecs = {
  atlantis_repo_allowlist = "github.com/your-org/*"
}


Configure terraform.tfvars
Fill in values like AWS region, GitHub app, VPC CIDRs, and repository webhook settings:

aws = {
  region  = "us-east-1"
  profile = ""
}

The webhook_secret will be used by GitHub and Atlantis to verify webhook authenticity.

Initialize Terraform by doing terraform init

Apply Infrastructure

terraform apply -var-file="terraform.tfvars"
