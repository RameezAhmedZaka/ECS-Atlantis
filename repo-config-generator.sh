# #!/bin/bash
# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: false
# parallel_apply: false
# projects:
# EOF

# # Check if a directory is a Terraform project
# is_terraform_project() {
#     local dir="$1"
#     [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
# }

# # Loop through top-level dirs (apps)
# for base_dir in */; do
#     [ -d "$base_dir" ] || continue
#     for app_dir in "$base_dir"*/; do
#         [ -d "$app_dir" ] || continue
#         if is_terraform_project "$app_dir"; then
#             app_name="$(basename "$app_dir")"

#             # Add project entries for each environment
#             for env in helia staging production; do
#                 env_path="${app_dir}env/${env}"
#                 [ -d "$env_path" ] || continue

#                 cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-${env}
#     dir: $env_path
#     autoplan:
#       enabled: true
#       when_modified:
#         - "../../*.tf"
#         - "../../config/*.tfvars"
#         - "../../env/*/*"
#     terraform_version: v1.6.6
#     workflow: ${env}_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#             done
#         fi
#     done
# done

# # Fixed workflows using only run steps (everything else unchanged)
# cat >> atlantis.yaml << 'EOF'
# workflows:
#   production_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/production/prod.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/production.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   staging_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl

#             terraform init -backend-config=env/staging/stage.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/stage.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   helia_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/helia/helia.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/helia.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE
# EOF


#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Start atlantis.yaml
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Check if a directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Loop through top-level dirs (apps)
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name="$(basename "$app_dir")"
            base_name="${base_dir%/}"

            # Create one project per app that handles all environments
            cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_name}-${app_name}
    dir: .
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/*/*"
    terraform_version: v1.6.6
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
        fi
    done
done

# Single workflow that detects environment based on changed files
cat >> atlantis.yaml << 'EOF'
workflows:
  default:
    plan:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            echo "Working directory: $PWD"
            
            # Detect environment based on changed files
            ENVIRONMENT="production"  # default
            BACKEND_CONFIG="env/production/prod.conf"
            VAR_FILE="config/production.tfvars"
            
            # Check which environment files were modified
            if [[ -n "$(git diff --name-only HEAD~1 | grep -E 'env/staging/|config/stage\.tfvars')" ]]; then
              ENVIRONMENT="staging"
              BACKEND_CONFIG="env/staging/stage.conf"
              VAR_FILE="config/stage.tfvars"
            elif [[ -n "$(git diff --name-only HEAD~1 | grep -E 'env/helia/|config/helia\.tfvars')" ]]; then
              ENVIRONMENT="helia"
              BACKEND_CONFIG="env/helia/helia.conf"
              VAR_FILE="config/helia.tfvars"
            elif [[ -n "$(git diff --name-only HEAD~1 | grep -E 'env/production/|config/production\.tfvars')" ]]; then
              ENVIRONMENT="production"
              BACKEND_CONFIG="env/production/prod.conf"
              VAR_FILE="config/production.tfvars"
            fi
            
            echo "Detected environment: $ENVIRONMENT"
            
            # Store environment in file for apply phase
            echo "$ENVIRONMENT" > /tmp/current_environment.txt
            echo "$BACKEND_CONFIG" > /tmp/backend_config.txt
            echo "$VAR_FILE" > /tmp/var_file.txt

            cd "$(dirname "$PROJECT_DIR")"
            
            # Initialize and plan
            rm -rf .terraform .terraform.lock.hcl 
            terraform init -backend-config=$BACKEND_CONFIG -reconfigure -lock=false -input=false
            terraform plan -var-file=$VAR_FILE -lock-timeout=10m -out=$PLANFILE

    apply:
      steps:
        - run: |
            ENVIRONMENT=$(cat /tmp/current_environment.txt)
            BACKEND_CONFIG=$(cat /tmp/backend_config.txt)
            VAR_FILE=$(cat /tmp/var_file.txt)
            
            echo "Applying changes for environment: $ENVIRONMENT"
            echo "Using backend config: $BACKEND_CONFIG"
            echo "Using var file: $VAR_FILE"
            
            cd "$(dirname "$PROJECT_DIR")"

            # Re-initialize to ensure correct backend
            terraform init -backend-config=$BACKEND_CONFIG -reconfigure -lock=false -input=false
            terraform apply -auto-approve $PLANFILE
EOF