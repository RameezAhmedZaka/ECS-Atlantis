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

## NOTE: Create the github app first and than run terraform code.
## 🔑 GitHub Integration

Atlantis interacts with GitHub using a **GitHub App**.
- Create a GitHub App
- Go to GitHub → Settings → Developer settings → GitHub Apps → New GitHub App.
- Fill details:
   - Name: <unique-name>
   - Homepage URL: your project URL (optional) add the same as wehbook url.
   - Webhook URL: ```https://your-api-endpoint/atlantis/events```                        (api with default stage that you created using the terraform code but for now you won't have the api id so place any random id and afterwards after running the terraform code when you will get this update here.)
     may looks like this ```https://28werguykc3.execute-api.us-east-1.amazonaws.com/atlantis/events```
   - Add the secret the same secret that you pushed to secrets manager before.  
  
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
| Secrets           | Read-only |

### Subscribe to Events

- check_suite  
- check_run  
- issue_comment  
- pull_request  
- repository
- Pull request review
- Pull request review comment

 ### Create the App with key 
- Click Create GitHub App.
- Generate App Private Key
- Download the .pem file from the GitHub App dashboard. Keep it secure.
- Encode Private Key and than place both files in secrets manager using the below command.
  
## Covert into base64
```
base64 <file-name-downloaded.pem> > <file-name-want-to-create.base64>
```
Command may looks like base64 atlantis-app.2025-11-07.private-key.pem > atlantis-app.pem.base64.

### Create the Secrets for terraform code
Send the secret to secret manager
```
aws secretsmanager create-secret \
  --name "/github/app/atlantis" \ 
  --description "Atlantis GitHub App credentials" \
  --secret-string "$(jq -n \
    --arg webhook_secret 'webhook123' \
    --arg private_key "$(cat terragrunt-0987.2025-12-04.private-key.pem)" \
    --arg key_base64 "$(cat terragrunt.base64)" \
    '{webhook_secret: $webhook_secret, private_key: $private_key, key_base64: $key_base64}')"                 
```
### Instruction for secret manager command above:
- --name "name of the secrets in secret manager" in my case it is /github/app/atlantis
- --arg webhook_secret 'webhook123' the wehbook secret also place the same secret in the github app for authentication.
- --arg private_key "$(cat terragrunt-0987.2025-12-04.private-key.pem)" the pem file you downloaded.
- -arg key_base64 "$(cat terragrunt.base64)"  The pem file you converted into base64.
- Set the same name as "/github/app/atlantis" or if changing than update in atlantis/config/dev.tfvars for variable atlantis_secret.
- Specify region if you are not using default one. 

### Install GitHub App
- Install the App on selected repositories.
- Ensure permissions match Atlantis requirements.
- Get the app_id and installation_id that will be needed.
- The last numbers are installation id of url after installing the required repo on github app. ```https://github.com/settings/installations/987654```
### GitHub App Parameters in `atlantis/config/dev.tfvars`

```hcl
atlantis_secret = "/github/app/atlantis"

aws = {
  profile = ""                                           # mention profile
}
github_repositories_webhook = {
  github_owner               = ""                         # owner-of-github-app
  github_app_key_base64      = "/github/app/key_base64"   # base64 PEM file
  github_app_pem_file        = "/github/app/pem_file"     # PEM file as-is
  repositories               = [""]                       # repositories on which you want to run alantis and on which you installed github app      
  github_app_id              = ""                         # app_id
  github_app_installation_id = ""                         # installation id              
}

atlantis_ecs = {
  {
      name  = "ATLANTIS_REPO_ALLOWLIST"
      value = "github.com/<org-name>/*"                   # name of org  
    },
}

atlantis_api_gateway = {
  api_id                   = "xyz"                        # place the api_id that you created above
}
```
## 📁 Server-Side Configuration: atlantis/modules/ecs/server-atlantis.yaml
```
repos:
  - id: github.com/<org-name>/<repo-name>                  # change this configuration
    allow_custom_workflows: true
    allowed_overrides:
      - apply_requirements
      - workflow
      - plan_requirements
      - repo_locks
    apply_requirements: []
    repo_locking: false  
    pre_workflow_hooks:
      - run: |
          chmod +x ./repo-config-generator.sh              # place the file repo-config-generator.sh at root level of your repo that you installed.
          ./repo-config-generator.sh
        description: Generating configs
```
### Explanation:
- id: Repository this config applies to
- allow_custom_workflows: Enables custom Terraform workflows
- allowed_overrides: Permits repo-specific overrides
- pre_workflow_hooks: Runs scripts before Terraform operations

### 🚀 Atlantis Environment Configuration
```
    {
      name  = "ATLANTIS_PORT"
      value = "4141"
    },
    {
      name  = "ATLANTIS_REPO_ALLOWLIST"
      value = "github.com/RameezAhmedZaka/*"
    },
    {
      name  = "ATLANTIS_ENABLE_DIFF_MARKDOWN_FORMAT"
      value = "true"
    },
    {
      name  = "ATLANTIS_ALLOW_COMMANDS"
      value = "version,plan,apply,unlock,approve_policies"
    },
    {
      name  = "ATLANTIS_HIDE_UNCHANGED_PLAN_COMMENTS"
      value = "true"
    },
    {
      name  = "ATLANTIS_MAX_COMMENTS_PER_COMMAND"
      value = "0"
    },
    {
      name  = "ATLANTIS_GH_WEBHOOK_SECRET"
      value = data.aws_secretsmanager_secret_version.github_webhook_secret.secret_string
     }    
```
### Explanation:

- ATLANTIS_REPO_CONFIG_JSON: Loads server-side config from server-atlantis.yaml
- ATLANTIS_ALLOW_COMMANDS: Specifies allowed commands (plan, apply, etc.)
- ATLANTIS_HIDE_UNCHANGED_PLAN_COMMENTS: Hides plan comments when nothing changes
- ATLANTIS_PORT – Specifies the port on which the Atlantis server runs (here, port 4141).
- ATLANTIS_REPO_ALLOWLIST – Limits Atlantis to only operate on repositories matching github.com/RameezAhmedZaka/*.
- ATLANTIS_ENABLE_DIFF_MARKDOWN_FORMAT – Enables Markdown formatting for Terraform plan diffs in pull requests.
- ATLANTIS_MAX_COMMENTS_PER_COMMAND – Sets the maximum number of comments per command (0 = unlimited).
- ATLANTIS_GH_WEBHOOK_SECRET – Stores the GitHub webhook secret (fetched securely from AWS Secrets Manager).

## Atlantis Permissions
```
resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.backend_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

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
app1
├── backend.tf
├── config
│   ├── helia.tfvars
│   ├── production.tfvars
│   └── stage.tfvars
├── env
│   ├── helia
│   │   └── helia.conf
│   ├── production
│   │   └── prod.conf
│   └── staging
│       └── stage.conf
├── main.tf
├── providers.tf
└── variables.tf

```

### ⚙️ Terraform Configuration
aws = {
  region  = "us-east-1"
  profile = ""
}
- Clone the code
- Change this configuration according to your need for s3 backend
```
bucket  = "tf-state-test123"
key     = "terraform.tfstate"
region  = "us-east-1"
```
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
git checkout -b my-infrastructure-change
vim application/app1/main.tf
git add .
git commit -m "Add new resource to app1"
git push origin my-infrastructure-change
```
- Create PR on GitHub for main branch
- Atlantis automatically runs 'terraform plan' and comments results
- Review plan in PR comments
- Comment 'atlantis apply' to deploy changes

### 4. What Happens Behind the Scenes
- GitHub App notifies Atlantis about PR
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
- Webhook not delivered → Check GitHub App recent deliveries. Go to Github App → advanced → Recent deliveries.
- Plan not running → Verify folder structure and Terraform file requirements
- Permission errors → Ensure GitHub App has correct access
- Configuration not generated → Ensure repo-config-generator.sh is executable

### Debugging Tips:
- Check ECS task logs in CloudWatch
- Ensure all required Terraform files exist(main.tf, variables.tf, provider.tf)
- Ensure environment folders (e.g production, staging, helia) exist
- Ensure that you have made changes in the .tf files before making the PR.
