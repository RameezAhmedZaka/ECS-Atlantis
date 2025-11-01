#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Start atlantis.yaml
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: false  # Disable automerge for debugging
parallel_plan: false
parallel_apply: false  # Force serial execution
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

            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue

                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: $env_path
    autoplan:
      enabled: true # Disable autoplan to prevent conflicts
      when_modified:
        - "../../*.tf"
        - "../../config/*.tfvars"
        - "../../env/*/*"
    terraform_version: v1.6.6
    workflow: multi_env_workflow
    apply_requirements:
      - approved
PROJECT_EOF
            done
        fi
    done
done

# Workflows section with proper directory handling
cat >> atlantis.yaml << 'EOF'
workflows:
  multi_env_workflow:
    plan:
      steps:
        - run: |
            set -e
            echo "Starting plan for $PROJECT_NAME in directory: $PROJECT_DIR"
            
            PLANFILE="plan_${PROJECT_NAME}.tfplan"
            # Clean any existing plan files
            rm -f "plan_*.tfplan"
            
            case "$PROJECT_NAME" in
              *-production)
                ENV="production"
                BACKEND_CONFIG="../../env/production/prod.conf"
                VAR_FILE="../../config/production.tfvars"
                ;;
              *-staging)
                ENV="staging"
                BACKEND_CONFIG="../../env/staging/stage.conf"
                VAR_FILE="../../config/stage.tfvars"
                ;;
              *-helia)
                ENV="helia"
                BACKEND_CONFIG="../../env/helia/helia.conf"
                VAR_FILE="../../config/helia.tfvars"
                ;;
              *)
                ENV="default"
                BACKEND_CONFIG=""
                VAR_FILE=""
                ;;
            esac

            echo "Planning for environment: $ENV"
            echo "Project directory: $PWD"
            echo "Using backend config: $BACKEND_CONFIG"
            echo "Using var file: $VAR_FILE"

            # Clean up any existing terraform state in the current directory
            rm -rf .terraform
            rm -f .terraform.lock.hcl
            rm -f terraform.tfstate*
            rm -f *.tfplan

            # Initialize in the current project directory
            if [ -f "$BACKEND_CONFIG" ]; then
              echo "Initializing with backend config: $BACKEND_CONFIG"
              terraform init -backend-config="$BACKEND_CONFIG" -input=false -reconfigure
            else
              echo "Initializing without backend config"
              terraform init -input=false -reconfigure
            fi

            # Run plan
            if [ -f "$VAR_FILE" ]; then
              echo "Running plan with var file: $VAR_FILE"
              terraform plan -lock-timeout=20m -var-file="$VAR_FILE" -out="$PLANFILE"
            else
              echo "Running plan without var file"
              terraform plan -lock-timeout=20m -out="$PLANFILE"
            fi

            echo "Plan completed successfully"

    apply:
      steps:
        - run: |
            set -e
            echo "Starting apply for $PROJECT_NAME in directory: $PROJECT_DIR"
            
            PLANFILE="plan_${PROJECT_NAME}.tfplan"

            case "$PROJECT_NAME" in
              *-production)
                ENV="production"
                BACKEND_CONFIG="../../env/production/prod.conf"
                VAR_FILE="../../config/production.tfvars"
                ;;
              *-staging)
                ENV="staging"
                BACKEND_CONFIG="../../env/staging/stage.conf"
                VAR_FILE="../../config/stage.tfvars"
                ;;
              *-helia)
                ENV="helia"
                BACKEND_CONFIG="../../env/helia/helia.conf"
                VAR_FILE="../../config/helia.tfvars"
                ;;
              *)
                ENV="default"
                BACKEND_CONFIG=""
                VAR_FILE=""
                ;;
            esac

            echo "Applying for environment: $ENV"
            echo "Project directory: $PWD"

            # Clean up any existing terraform state in the current directory
            rm -rf .terraform
            rm -f .terraform.lock.hcl
            rm -f terraform.tfstate*

            # Reinitialize to ensure clean state
            if [ -f "$BACKEND_CONFIG" ]; then
              echo "Reinitializing with backend config: $BACKEND_CONFIG"
              terraform init -backend-config="$BACKEND_CONFIG" -input=false -reconfigure
            else
              echo "Reinitializing without backend config"
              terraform init -input=false -reconfigure
            fi

            if [ -f "$PLANFILE" ]; then
              echo "Applying plan: $PLANFILE"
              terraform apply -input=false -lock-timeout=25m -auto-approve "$PLANFILE"
              
              # Clean up plan file after successful apply
              rm -f "$PLANFILE"
              echo "Apply completed successfully"
            else
              echo "Error: Plan file $PLANFILE not found"
              ls -la *.tfplan || echo "No plan files found"
              exit 1
            fi
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
#               timeout 600 terraform apply -input=false -lock-timeout=5m  -auto-approve "$PLANFILE" || {
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