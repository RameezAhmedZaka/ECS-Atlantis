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

# Function to check if a directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Loop through apps
for base_dir in application/*/; do
    [ -d "$base_dir" ] || continue
    app_name="$(basename "$base_dir")"

    # Loop through environments under each app
    for env_dir in "$base_dir"env/*/; do
        [ -d "$env_dir" ] || continue
        env_name="$(basename "$env_dir")"

        # Skip if not Terraform project (we check two dirs up, since env dirs only hold confs)
        if is_terraform_project "$base_dir"; then
            project_name="${app_name}-${env_name}"

            cat >> atlantis.yaml << PROJECT_EOF
  - name: ${project_name}
    dir: ${env_dir}
    autoplan:
      enabled: true
      when_modified:
        - "../../*.tf"
        - "../../config/*.tfvars"
        - "../../env/*/*"
    terraform_version: v1.6.6
    workflow: multi_env_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
        fi
    done
done

# Workflows section
cat >> atlantis.yaml << 'EOF'
workflows:
  multi_env_workflow:
    plan:
      steps:
        - run: |
            PLANFILE="plan_${PROJECT_NAME}.tfplan"

            case "$PROJECT_NAME" in
              *-production)
                ENV="production"
                BACKEND_CONFIG="env/production/prod.conf"
                VAR_FILE="config/production.tfvars"
                ;;
              *-staging)
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
              *-helia)
                ENV="helia"
                BACKEND_CONFIG="env/helia/helia.conf"
                VAR_FILE="config/helia.tfvars"
                ;;
              *)
                ENV="default"
                BACKEND_CONFIG=""
                VAR_FILE=""
                ;;
            esac

            echo "Planning for environment: $ENV"
            echo "Using backend config: $BACKEND_CONFIG"
            echo "Using var file: $VAR_FILE"

            # Move two directories up to main Terraform project
            cd "$(dirname "$PROJECT_DIR")/../.."

            if [ -f "$BACKEND_CONFIG" ]; then
              timeout 300 terraform init \
                -backend-config="$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure
            fi

            if [ -f "$VAR_FILE" ]; then
              timeout 300 terraform plan $DESTROY_FLAG \
                         -var-file="$VAR_FILE" \
                         -out="$PLANFILE"
            else
              terraform plan $DESTROY_FLAG -out="$PLANFILE"
            fi

    apply:
      steps:
        - run: |
            PLANFILE="plan_${PROJECT_NAME}.tfplan"

            case "$PROJECT_NAME" in
              *-production)
                ENV="production"
                BACKEND_CONFIG="env/production/prod.conf"
                VAR_FILE="config/production.tfvars"
                ;;
              *-staging)
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
              *-helia)
                ENV="helia"
                BACKEND_CONFIG="env/helia/helia.conf"
                VAR_FILE="config/helia.tfvars"
                ;;
              *)
                ENV="default"
                BACKEND_CONFIG=""
                VAR_FILE=""
                ;;
            esac

            echo "Applying for environment: $ENV"

            # Move two directories up to main Terraform project
            cd "$(dirname "$PROJECT_DIR")/../.."

            if [ -f "$BACKEND_CONFIG" ]; then
              timeout 300 terraform init \
                -backend-config="$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure > /dev/null 2>&1
            fi

            if [ -f "$PLANFILE" ]; then
              timeout 600 terraform apply -input=false -auto-approve "$PLANFILE" || {
                echo "Apply failed for $PLANFILE"
              }
            else
              timeout 600 terraform apply -var-file="$VAR_FILE" -input=false -auto-approve || {
                echo "Apply failed for $PROJECT_DIR"
              }
            fi
EOF




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

# # Loop through all top-level directories (e.g., application, db, network)
# for base_dir in */; do
#     [ -d "$base_dir" ] || continue

#     # Loop through each subdirectory
#     for sub_dir in "$base_dir"*/; do
#         [ -d "$sub_dir" ] || continue

#         if is_terraform_project "$sub_dir"; then
#             app_name="$(basename "$sub_dir")"
#             envs=$(get_environments "$sub_dir")

#             if [ -z "$envs" ]; then
#                 # Single project without environments
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
#                 # Multiple environments, keep dir as actual TF folder
#                 for env in $envs; do
#                     cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-${env}
#     dir: $sub_dir
#     autoplan:
#       enabled: true
#       when_modified:
#         - "*.tf"
#         - "config/${env}.tfvars"
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
#             PLANFILE="plan_\${PROJECT_NAME}.tfplan"

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
#                 ENV="default"
#                 BACKEND_CONFIG=""
#                 VAR_FILE=""
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
#             PLANFILE="plan_\${PROJECT_NAME}.tfplan"

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
#                 ENV="default"
#                 BACKEND_CONFIG=""
#                 VAR_FILE=""
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
