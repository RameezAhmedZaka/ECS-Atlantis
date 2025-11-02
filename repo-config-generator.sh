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
    base_dir="${base_dir%/}"
    
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        app_dir="${app_dir%/}"
        app_name="$(basename "$app_dir")"
        
        if is_terraform_project "$app_dir"; then
            # Create one project per app with dynamic environment detection
            cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir}-${app_name}
    dir: ${app_dir}
    autoplan:
      enabled: false
    terraform_version: v1.6.6
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
        fi
    done
done

# Add dynamic workflow that detects environment from changed files
cat >> atlantis.yaml << 'EOF'

workflows:
  dynamic_environment:
    plan:
      steps:
        - run: |
            echo "Detecting environment for project: $PROJECT_NAME"
            
            # Get the app directory from project name
            APP_DIR="$DIR"
            
            # Check which files were modified to determine environment
            if [ -n "$(git diff --name-only HEAD~1 HEAD -- "${APP_DIR}/env/production/" 2>/dev/null || true)" ]; then
              ENV="production"
              BACKEND_CONFIG="env/production/prod.conf"
              VAR_FILE="config/production.tfvars"
            elif [ -n "$(git diff --name-only HEAD~1 HEAD -- "${APP_DIR}/env/staging/" 2>/dev/null || true)" ]; then
              ENV="staging"
              BACKEND_CONFIG="env/staging/stage.conf"
              VAR_FILE="config/stage.tfvars"
            elif [ -n "$(git diff --name-only HEAD~1 HEAD -- "${APP_DIR}/env/helia/" 2>/dev/null || true)" ]; then
              ENV="helia"
              BACKEND_CONFIG="env/helia/helia.conf"
              VAR_FILE="config/helia.tfvars"
            else
              # If no specific environment changed, plan for all environments or use default
              ENV="all"
              BACKEND_CONFIG="env/production/prod.conf"
              VAR_FILE="config/production.tfvars"
            fi
            
            echo "Selected environment: $ENV"
            echo "backend_config: $BACKEND_CONFIG"
            echo "var_file: $VAR_FILE"
            
            # Store environment in file for apply phase
            echo "$ENV" > /tmp/current_env.txt
            echo "$BACKEND_CONFIG" > /tmp/backend_config.txt
            echo "$VAR_FILE" > /tmp/var_file.txt
            
            # Initialize and plan
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config="$BACKEND_CONFIG" -reconfigure -lock=false -input=false
            terraform plan -var-file="$VAR_FILE" -lock-timeout=10m -out=tfplan.out
            
        - run: |
            # Copy plan file with environment context
            ENV=$(cat /tmp/current_env.txt)
            cp tfplan.out "../${PROJECT_NAME}-${ENV}-tfplan.out"
            echo "Plan file saved as: ${PROJECT_NAME}-${ENV}-tfplan.out"

    apply:
      steps:
        - run: |
            echo "Applying changes for project: $PROJECT_NAME"
            
            # Find the correct plan file based on environment
            APP_DIR="$DIR"
            ENV=$(cat /tmp/current_env.txt 2>/dev/null || echo "production")
            BACKEND_CONFIG=$(cat /tmp/backend_config.txt 2>/dev/null || echo "env/production/prod.conf")
            VAR_FILE=$(cat /tmp/var_file.txt 2>/dev/null || echo "config/production.tfvars")
            
            PLAN_FILE="../${PROJECT_NAME}-${ENV}-tfplan.out"
            
            if [ ! -f "$PLAN_FILE" ]; then
              echo "Error: Plan file not found: $PLAN_FILE"
              echo "Available plan files:"
              ls -la ../*.out 2>/dev/null || echo "No plan files found"
              exit 1
            fi
            
            echo "Using plan file: $PLAN_FILE"
            echo "Environment: $ENV"
            
            # Initialize with same backend config
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config="$BACKEND_CONFIG" -reconfigure -lock=false -input=false
            
            # Apply the plan
            terraform apply -auto-approve "$PLAN_FILE"
            
            # Cleanup
            rm -f "$PLAN_FILE"

EOF





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
#             terraform init -backend-config=env/production/prod.conf -reconfigure -lock=false -input=false
#             terraform plan -var-file=config/production.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: terraform apply -auto-approve $PLANFILE

#   staging_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl

#             terraform init -backend-config=env/staging/stage.conf -reconfigure -lock=false -input=false
#             terraform plan -var-file=config/stage.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: terraform apply -auto-approve $PLANFILE

#   helia_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/helia/helia.conf -reconfigure -lock=false -input=false
#             terraform plan -var-file=config/helia.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: terraform apply -auto-approve $PLANFILE
# EOF



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
#     workflow: multi_env_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#             done
#         fi
#     done
# done

# # Workflows section (unchanged)
# cat >> atlantis.yaml << 'EOF'
# workflows:
#   multi_env_workflow:
#     plan:
#       steps:
#         - run: |
#             PLANFILE="plan_${PROJECT_NAME}.tfplan"

#             case "$PROJECT_NAME" in
#               *-production)
#                 ENV="production"
#                 BACKEND_CONFIG="env/production/prod.conf"
#                 VAR_FILE="config/production.tfvars"
#                 ;;
#               *-staging)
#                 ENV="staging"
#                 BACKEND_CONFIG="env/staging/stage.conf"
#                 VAR_FILE="config/stage.tfvars"
#                 ;;
#               *-helia)
#                 ENV="helia"
#                 BACKEND_CONFIG="env/helia/helia.conf"
#                 VAR_FILE="config/helia.tfvars"
#                 ;;
#               *)
#                 ENV="default"
#                 BACKEND_CONFIG=""
#                 VAR_FILE=""
#                 ;;
#             esac

#             echo "Planning for environment: $ENV"
#             echo "Using backend config: $BACKEND_CONFIG"
#             echo "Using var file: $VAR_FILE"

#             # Move two directories up to main Terraform project
#             cd "$(dirname "$PROJECT_DIR")/../.."

#             rm -rf .terraform

#             if [ -f "$BACKEND_CONFIG" ]; then
#               timeout 300 terraform init \
#                 -backend-config="$BACKEND_CONFIG" \
#                 -input=false -reconfigure > /dev/null 2>&1
#             else
#               terraform init -input=false -reconfigure
#             fi

#             if [ -f "$VAR_FILE" ]; then
#               timeout 300 terraform plan -lock-timeout=5m  \
#                          -var-file="$VAR_FILE" \
#                          -out="$PLANFILE"
#             else
#               terraform plan $DESTROY_FLAG -out="$PLANFILE"
#             fi

#     apply:
#       steps:
#         - run: |
#             PLANFILE="plan_${PROJECT_NAME}.tfplan"

#             case "$PROJECT_NAME" in
#               *-production)
#                 ENV="production"
#                 BACKEND_CONFIG="env/production/prod.conf"
#                 VAR_FILE="config/production.tfvars"
#                 ;;
#               *-staging)
#                 ENV="staging"
#                 BACKEND_CONFIG="env/staging/stage.conf"
#                 VAR_FILE="config/stage.tfvars"
#                 ;;
#               *-helia)
#                 ENV="helia"
#                 BACKEND_CONFIG="env/helia/helia.conf"
#                 VAR_FILE="config/helia.tfvars"
#                 ;;
#               *)
#                 ENV="default"
#                 BACKEND_CONFIG=""
#                 VAR_FILE=""
#                 ;;
#             esac

#             echo "Applying for environment: $ENV"

#             # Move two directories up to main Terraform project
#             cd "$(dirname "$PROJECT_DIR")/../.."

#             # if [ -f "$BACKEND_CONFIG" ]; then
#             #   timeout 300 terraform init \
#             #     -backend-config="$BACKEND_CONFIG" \
#             #     -input=false -reconfigure > /dev/null 2>&1
#             # else
#             #   terraform init -input=false -reconfigure > /dev/null 2>&1
#             # fi

#             if [ -f "$PLANFILE" ]; then
#               timeout 600 terraform apply -input=false -lock-timeout=5m  -lock=false -auto-approve "$PLANFILE" || {
#                 echo "Apply failed for $PLANFILE"
#               }
#             else
#               {
#                 echo "Apply failed for $PROJECT_DIR"
#               }
#             fi
# EOF







# #!/bin/bash
# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Create base atlantis.yaml with document start
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: false
# parallel_apply: false
# projects:
# EOF

# # Function to check if directory is a Terraform project
# is_terraform_project() {
#     local dir="$1"
#     [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
# }

# # Function to get environments for an app
# get_environments() {
#     local app_dir="$1"
#     local envs=()
#     declare -A env_map=( ["production"]="production" ["staging"]="stage" ["helia"]="helia" )
#     for env in "${!env_map[@]}"; do
#         tfvars_file="$app_dir/config/${env_map[$env]}.tfvars"
#         env_dir="$app_dir/env/$env"
#         if [ -f "$tfvars_file" ] && [ -d "$env_dir" ]; then
#             envs+=("$env")
#         fi
#     done
#     echo "${envs[@]}"
# }

# # Array to track project names
# declare -a project_names=()

# # Loop through all top-level directories (e.g., application, db, network, etc.)
# for base_dir in */; do
#     [ -d "$base_dir" ] || continue

#     # Loop through each subdirectory (e.g., application/app1, db/mysql)
#     for sub_dir in "$base_dir"*/; do
#         [ -d "$sub_dir" ] || continue

#         if is_terraform_project "$sub_dir"; then
#             app_name="$(basename "$sub_dir")"
#             envs=$(get_environments "$sub_dir")

#             if [ -z "$envs" ]; then
#                 cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-default
#     dir: $sub_dir
#     autoplan:
#       enabled: true
#       when_modified:
#         - "*.tf"
#         - "config/*.tfvars"
#         - "env/*/*"
#     terraform_version: v1.6.6
#     workflow: multi_env_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#                 project_names+=("${base_dir%/}-${app_name}-default")
#             else
#                 for env in $envs; do
#                     cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-${env}
#     dir: $sub_dir
#     autoplan:
#       enabled: true
#       when_modified:
#         - "*.tf"
#         - "config/*.tfvars"
#         - "env/$env/*"
#     terraform_version: v1.6.6
#     workflow: multi_env_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#                     project_names+=("${base_dir%/}-${app_name}-${env}")
#                 done
#             fi
#         fi
#     done
# done

# echo "Total projects configured: ${#project_names[@]}"
# echo "Project names: ${project_names[*]}"

# # Workflows section
# cat >> atlantis.yaml <<-EOF
# workflows:
#   multi_env_workflow:
#     plan:
#       steps:  
#         - run: |
#             PLANFILE="plan_${PROJECT_NAME}.tfplan"

#             case "\$PROJECT_NAME" in
#               *-production)
#                 ENV="production"
#                 BACKEND_CONFIG="env/production/prod.conf"
#                 VAR_FILE="config/production.tfvars"
#                 ;;
#               *-staging)
#                 ENV="staging"
#                 BACKEND_CONFIG="env/staging/stage.conf"
#                 VAR_FILE="config/stage.tfvars"
#                 ;;
#               *-helia)
#                 ENV="helia"
#                 BACKEND_CONFIG="env/helia/helia.conf"
#                 VAR_FILE="config/helia.tfvars"
#                 ;;
#               *)
#                 ENV="staging"
#                 BACKEND_CONFIG="env/staging/stage.conf"
#                 VAR_FILE="config/stage.tfvars"
#                 ;;
#             esac

#             echo "Planning for environment: \$ENV"
#             echo "Using backend config: \$BACKEND_CONFIG"
#             echo "Using var file: \$VAR_FILE"
#             echo "Destroy flag: \$DESTROY_FLAG"

#             cd "\$PROJECT_DIR"

#             if [ -f "\$BACKEND_CONFIG" ]; then
#               timeout 300 terraform init \
#                 -backend-config="\$BACKEND_CONFIG" \
#                 -input=false -reconfigure > /dev/null 2>&1
#             else
#               terraform init -input=false -reconfigure
#             fi

#             if [ -f "\$VAR_FILE" ]; then
#               timeout 300 terraform plan \$DESTROY_FLAG \
#                          -var-file="\$VAR_FILE" \
#                          -out="\$PLANFILE"
#             else
#               terraform plan \$DESTROY_FLAG -out="\$PLANFILE"
#             fi

#     apply:
#       steps:
#         - run: |
#             PLANFILE="plan_${PROJECT_NAME}.tfplan"

#             case "\$PROJECT_NAME" in
#               *-production)
#                 ENV="production"
#                 BACKEND_CONFIG="env/production/prod.conf"
#                 VAR_FILE="config/production.tfvars"
#                 ;;
#               *-staging)
#                 ENV="staging"
#                 BACKEND_CONFIG="env/staging/stage.conf"
#                 VAR_FILE="config/stage.tfvars"
#                 ;;
#               *-helia)
#                 ENV="helia"
#                 BACKEND_CONFIG="env/helia/helia.conf"
#                 VAR_FILE="config/helia.tfvars"
#                 ;;
#               *)
#                 ENV="staging"
#                 BACKEND_CONFIG="env/staging/stage.conf"
#                 VAR_FILE="config/stage.tfvars"
#                 ;;
#             esac

#             echo "Applying for environment: \$ENV"

#             cd "\$PROJECT_DIR"

#             if [ -f "\$BACKEND_CONFIG" ]; then
#               timeout 300 terraform init \
#                 -backend-config="\$BACKEND_CONFIG" \
#                 -input=false -reconfigure > /dev/null 2>&1
#             else
#               terraform init -input=false -reconfigure > /dev/null 2>&1
#             fi

#             # Apply the plan if it exists, otherwise do a raw apply with var-file
#             if [ -f "\$PLANFILE" ]; then
#               timeout 600 terraform apply -input=false -auto-approve "\$PLANFILE" || {
#                 echo "Apply failed for \$PLANFILE"
#               }
#             else
#               timeout 600 terraform apply -var-file="\$VAR_FILE" -input=false -auto-approve || {
#                 echo "Apply failed for \$PROJECT_DIR"
#               }
#             fi
# EOF