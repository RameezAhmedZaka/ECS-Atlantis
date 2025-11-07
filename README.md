# Atlantis on AWS ECS with API Gateway

![Terraform](https://img.shields.io/badge/Terraform-v1.6.6-blue?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-Cloud-orange?logo=amazon-aws)
![GitHub Workflow](https://img.shields.io/badge/GitHub-Workflow-lightgrey?logo=github)

This Terraform project deploys Atlantis on **AWS ECS Fargate**, integrated with **GitHub** and exposed through **API Gateway** via a **VPC Link** and **internal Network Load Balancer**.

Atlantis enables GitOps-style workflows by automating `terraform plan` and `apply` actions based on pull request activity in GitHub.

---

## 📦 What's Deployed

- **VPC**: With public/private subnets and NAT Gateway  
- **ECS Fargate Service**: Runs the Atlantis container  
- **Internal NLB**: For network traffic routing inside the VPC  
- **API Gateway (REST)**: Publicly exposes Atlantis at `/atlantis`  
- **Security Groups**: Control traffic between components  
- **GitHub Webhook**: Automatically created and linked to your repository  

---
### Required Permissions

- Clone repositories  
- Comment on pull requests  
- Access GitHub APIs
  
### Create the api for terraform code
1. Create the API
```
aws apigatewayv2 create-api \
    --name atlantis-api \
    --protocol-type HTTP \
    --description "Atlantis HTTP API" \
    --region us-east-1
```


Note the id returned → this is your API_ID that will be used in terraform.tfvars

2. Deploy the API to a stage default 
```
aws apigatewayv2 create-stage \
    --api-id <api-id> \
    --stage-name '$default' \
    --auto-deploy


```

## 🔑 GitHub Integration

Atlantis interacts with GitHub using a **GitHub App**.
- Create a GitHub App
- Go to GitHub → Settings → Developer settings → GitHub Apps → New GitHub App.
- Fill details:
   - Name: <any-name>
   - Homepage URL: your project URL (optional)
   - Webhook URL: ```https://your-api-id/api-stage/atlantis/events```                        (api with stage that you created before)
     ```https://28werkfkkc3.execute-api.us-east-1.amazonaws.com/stage```        
   - Webhook Secret: random string added in terraform.tfvars
- Click Create GitHub App.
- Generate App Private Key
- Download the .pem file from the GitHub App dashboard. Keep it secure.
- Encode Private Key and than place both files in parameter store.

Store the Base64 key
```
aws ssm put-parameter \
  --name "/github/app/key_base64" \
  --value "$(cat name_of_file)" \
  --type "SecureString" \
  --overwrite
```
Store the PEM file
```
aws ssm put-parameter \
  --name "/github/app/pem_file" \
  --value "$(cat name_pem_file)" \
  --type "SecureString" \
  --overwrite
```

### GitHub App Permissions Table

| Category          | Permission |
|------------------|------------|
| Administration    | Read & write |
| Checks            | Read & write |
| Commit statuses   | Read & write |
| Contents          | Read & write |
| Issues            | Read & write |
| Metadata          | Read-only |
| Pull Requests     | Read & write |
| Webhooks          | Read & write |
| Actions           | Read-only |

### Subscribe to Events

- check_suite  
- check_run  
- issue_comment  
- pull_request  
- repository

### Install GitHub App
- Install the App on selected repositories.
- Ensure permissions match Atlantis requirements.
- Get the app_id and installation_id that will be needed. You will the installation_id at the url after installation that can looks like this https://github.com/settings/installations/987654 
- The last numbers are installation id. (https://github.com/settings/installations/987654) 

### GitHub App Parameters in `terraform.tfvars`

```hcl
github_repositories_webhook = {
  github_owner               = "owner-of-github-app"
  github_app_key_base64      = "/github/app/key_base64"   # base64 PEM file
  github_app_pem_file        = "/github/app/pem_file"     # PEM file as-is
  repositories               = ["terraform"]              # repositories to add webhook to
  webhook_secret             = "yrdjf@edstru"             # add wehbook secrets (random string)       
  github_app_id              = "github-app-id"            # app_id
  github_app_installation_id = "xyz"                      # installation id              
}

atlantis_ecs = {
  atlantis_repo_allowlist = "github.com/your-org/*"       # add this too in terraform.tfvars
}

atlantis_api_gateway = {
  api_id                   = "xyz"                        # place the api_id that you created above
}
```

### 🚀 Atlantis Environment Configuration
```
{
  name: "ATLANTIS_REPO_CONFIG_JSON",
  value: jsonencode(yamldecode(file("${path.module}/server-atlantis.yaml"))),
},
{
  name: "ATLANTIS_ALLOW_COMMANDS",
  value: "version,plan,apply,unlock,approve_policies"
},
{
  name: "ATLANTIS_HIDE_UNCHANGED_PLAN_COMMENTS",
  value: "true"
}
```
### Explanation:

- ATLANTIS_REPO_CONFIG_JSON: Loads server-side config from server-atlantis.yaml
- ATLANTIS_ALLOW_COMMANDS: Specifies allowed commands (plan, apply, etc.)
- ATLANTIS_HIDE_UNCHANGED_PLAN_COMMENTS: Hides plan comments when nothing changes

## Atlantis Permissions
```
resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.backend_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

## 📁 Server-Side Configuration: server-atlantis.yaml
```
repos:
  - id: github.com/<org-name>/<repo-name>                     #change this configuration
    allow_custom_workflows: true 
    allowed_overrides:
      - apply_requirements
      - workflow
      - plan_requirements
    apply_requirements: []
    pre_workflow_hooks:
      - run: |
          echo "Running config-generator from $(pwd)"
          ls -la
          chmod +x ./repo-config-generator.sh || echo "Script not found or not executable"         
          ./repo-config-generator.sh || (echo "Script failed !" && exit 1)                  # File must be placed at root level
        description: Generating configs
```
### Explanation:
- id: Repository this config applies to
- allow_custom_workflows: Enables custom Terraform workflows
- allowed_overrides: Permits repo-specific overrides
- pre_workflow_hooks: Runs scripts before Terraform operations

## 🪄 The Magic Script: repo-config-generator.sh
### Functionality:
- Detects Terraform projects (main.tf, variables.tf, providers.tf)
- Creates separate Atlantis projects per environment (helia, staging, production)
- Generates custom workflows
- Automatically runs plans on relevant changes

### Key Features:
- Dynamic project detection
- Multi-environment support
- Custom workflows
- Auto-planning

## 📂 Required Folder Structure
Make sure you are following this folder structure for any app and than you can place at root or at folder.
```
└── db71
    ├── backend.tf
    ├── config
    │   ├── helia.tfvars
    │   ├── production.tfvars
    │   └── stage.tfvars
    ├── env
    │   └── staging
    │       └── stage.conf
    ├── main.tf
    ├── providers.tf
    └── variables.tf
```
Overall Structure can look like this
```
repository/
.
├── application
│   ├── network
│   │   ├── backend.tf
│   │   ├── config
│   │   │   ├── helia.tfvars
│   │   │   ├── production.tfvars
│   │   │   └── stage.tfvars
│   │   ├── env
│   │   │   ├── helia
│   │   │   │   └── helia.conf
│   │   │   ├── production
│   │   │   │   └── prod.conf
│   │   │   └── staging
│   │   │       └── stage.conf
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   └── variables.tf
│   └── rdot
│       ├── app11
│       │   ├── backend.tf
│       │   ├── config
│       │   │   ├── helia.tfvars
│       │   │   ├── production.tfvars
│       │   │   └── stage.tfvars
│       │   ├── db1
│       │   │   ├── backend.tf
│       │   │   ├── config
│       │   │   │   ├── helia.tfvars
│       │   │   │   ├── production.tfvars
│       │   │   │   └── stage.tfvars
│       │   │   ├── env
│       │   │   │   └── production
│       │   │   │       └── prod.conf
│       │   │   ├── main.tf
│       │   │   ├── providers.tf
│       │   │   └── variables.tf
│       │   ├── env
│       │   │   ├── helia
│       │   │   │   └── helia.conf
│       │   │   ├── production
│       │   │   │   └── prod.conf
│       │   │   └── staging
│       │   │       └── stage.conf
│       │   ├── main.tf
│       │   ├── providers.tf
│       │   └── variables.tf
│       ├── backend.tf
│       ├── config
│       │   ├── helia.tfvars
│       │   ├── production.tfvars
│       │   ├── rameez.tfvars
│       │   └── stage.tfvars
│       ├── env
│       │   ├── helia
│       │   │   └── helia.conf
│       │   ├── production
│       │   │   └── prod.conf
│       │   ├── rameez
│       │   │   └── rame.conf
│       │   └── staging
│       │       └── stage.conf
│       ├── main.tf
│       ├── providers.tf
│       └── variables.tf
├── db
│   └── db71
│       ├── backend.tf
│       ├── config
│       │   ├── helia.tfvars
│       │   ├── production.tfvars
│       │   └── stage.tfvars
│       ├── env
│       │   └── staging
│       │       └── stage.conf
│       ├── main.tf
│       ├── providers.tf
│       └── variables.tf
└── repo-config-generator.sh

```

### ⚙️ Terraform Configuration
aws = {
  region  = "us-east-1"
  profile = ""
}
Clone the code 
```
cd atlantis
```
Initialize Terraform:
```
terraform init -backend-config=./dev/dev.conf
```
Apply Infrastructure:
```
terraform apply -var-file=./config/dev.tfvars
```
## 🎯 How to Trigger Atlantis
### 1. Pull Request Workflow (Automatic)
- Create a PR modifying .tf files against main branch
- Atlantis detects changes via webhook
- Runs repo-config-generator.sh
- Runs terraform plan per affected project/environment
- Posts plan results in PR comments

### 2. Manual Commands
```
atlantis plan                 # Plan all projects
atlantis plan -p project-name # Plan specific project
atlantis apply                # Apply all planned changes
atlantis apply -p project-name# Apply specific project
```
### 3. Example Workflow
```
git checkout -b feature/my-infrastructure-change
vim application/app1/main.tf
git add .
git commit -m "Add new resource to app1"
git push origin feature/my-infrastructure-change
```
- Create PR on GitHub for main branch
- Atlantis automatically runs 'terraform plan' and comments results
- Review plan in PR comments
- Comment 'atlantis apply' to deploy changes

### 4. What Happens Behind the Scenes
- GitHub webhook notifies Atlantis about PR
- Atlantis clones repository
- Runs repo-config-generator.sh
- Generates atlantis.yaml with project definitions
- Executes terraform plan
- Posts formatted results to PR
- Waits for approval before applying changes 
- After successful changes pr is merged.


## 🔒 Security Features
- Repository Allowlist: Only allowed repositories can use Atlantis
- Command Restrictions: Only allowed commands are executed
- Webhook Secret Verification: Ensures webhook authenticity
- VPC Internal Routing: Runs inside private network
- API Gateway Protection: Public endpoint with authentication

## 🛠️ Troubleshooting
### Common Issues:
- Webhook not delivered → Check GitHub App recent deliveries. By going from Github App to advanced option
- Plan not running → Verify folder structure and Terraform file requirements
- Permission errors → Ensure GitHub App has correct access
- Configuration not generated → Ensure repo-config-generator.sh is executable

### Debugging Tips:
- Check ECS task logs in CloudWatch
- Verify GitHub webhook deliveries in repo settings
- Ensure all required Terraform files exist(main.tf, variables.tf, provider.tf)
- Ensure environment folders (e.g production, staging, helia) exist
