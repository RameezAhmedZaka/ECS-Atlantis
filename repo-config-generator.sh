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

#             if [ -f "$BACKEND_CONFIG" ]; then
#               timeout 300 terraform init \
#                 -backend-config="$BACKEND_CONFIG" \
#                 -input=false -reconfigure > /dev/null 2>&1
#             else
#               terraform init -input=false -reconfigure
#             fi

#             if [ -f "$VAR_FILE" ]; then
#               timeout 300 terraform plan $DESTROY_FLAG \
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

#             if [ -f "$BACKEND_CONFIG" ]; then
#               timeout 300 terraform init \
#                 -backend-config="$BACKEND_CONFIG" \
#                 -input=false -reconfigure > /dev/null 2>&1
#             else
#               terraform init -input=false -reconfigure > /dev/null 2>&1
#             fi

#             if [ -f "$PLANFILE" ]; then
#               timeout 600 terraform apply -input=false -auto-approve "$PLANFILE" || {
#                 echo "Apply failed for $PLANFILE"
#               }
#             else
#               timeout 600 terraform apply -var-file="$VAR_FILE" -input=false -auto-approve || {
#                 echo "Apply failed for $PROJECT_DIR"
#               }
#             fi
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

# Function to check if a directory is a Terraform project
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

            # Create ONE project per app
            cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}
    dir: $app_dir
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/*/*"
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
            bash -c '
            # Determine which environments to apply based on changed files
            ENVS=()

            if echo "$CHANGED_FILES" | grep -q "env/production/"; then
                ENVS+=("production")
            fi
            if echo "$CHANGED_FILES" | grep -q "env/staging/"; then
                ENVS+=("staging")
            fi
            if echo "$CHANGED_FILES" | grep -q "env/helia/"; then
                ENVS+=("helia")
            fi

            # If main Terraform files or config changed, apply to all
            if echo "$CHANGED_FILES" | grep -qE ".*\.tf|config/.*\.tfvars"; then
                ENVS=("production" "staging" "helia")
            fi

            echo "Environments to apply: ${ENVS[*]}"

            for ENV in "${ENVS[@]}"; do
                case "$ENV" in
                    production)
                        BACKEND_CONFIG="env/production/prod.conf"
                        VAR_FILE="config/production.tfvars"
                        ;;
                    staging)
                        BACKEND_CONFIG="env/staging/stage.conf"
                        VAR_FILE="config/stage.tfvars"
                        ;;
                    helia)
                        BACKEND_CONFIG="env/helia/helia.conf"
                        VAR_FILE="config/helia.tfvars"
                        ;;
                esac

                echo "Processing environment: $ENV"
                echo "Backend config: $BACKEND_CONFIG"
                echo "Vars file: $VAR_FILE"

                cd "$PROJECT_DIR"

                # Terraform init
                if [ -f "$BACKEND_CONFIG" ]; then
                    terraform init -backend-config="$BACKEND_CONFIG" -input=false -reconfigure
                else
                    terraform init -input=false -reconfigure
                fi

                # Terraform plan
                PLANFILE="plan_${ENV}.tfplan"
                if [ -f "$VAR_FILE" ]; then
                    terraform plan -var-file="$VAR_FILE" -out="$PLANFILE"
                else
                    terraform plan -out="$PLANFILE"
                fi
            done

    apply:
      steps:
        - run: |
            # Determine which environments to apply based on changed files
            ENVS=()

            if echo "$CHANGED_FILES" | grep -q "env/production/"; then
                ENVS+=("production")
            fi
            if echo "$CHANGED_FILES" | grep -q "env/staging/"; then
                ENVS+=("staging")
            fi
            if echo "$CHANGED_FILES" | grep -q "env/helia/"; then
                ENVS+=("helia")
            fi

            # If main Terraform files or config changed, apply to all
            if echo "$CHANGED_FILES" | grep -qE ".*\.tf|config/.*\.tfvars"; then
                ENVS=("production" "staging" "helia")
            fi

            echo "Environments to apply: ${ENVS[*]}"

            for ENV in "${ENVS[@]}"; do
                case "$ENV" in
                    production)
                        BACKEND_CONFIG="env/production/prod.conf"
                        VAR_FILE="config/production.tfvars"
                        ;;
                    staging)
                        BACKEND_CONFIG="env/staging/stage.conf"
                        VAR_FILE="config/stage.tfvars"
                        ;;
                    helia)
                        BACKEND_CONFIG="env/helia/helia.conf"
                        VAR_FILE="config/helia.tfvars"
                        ;;
                esac

                echo "Applying environment: $ENV"
                cd "$PROJECT_DIR"

                if [ -f "$BACKEND_CONFIG" ]; then
                    terraform init -backend-config="$BACKEND_CONFIG" -input=false -reconfigure > /dev/null 2>&1
                else
                    terraform init -input=false -reconfigure > /dev/null 2>&1
                fi

                PLANFILE="plan_${ENV}.tfplan"
                if [ -f "$PLANFILE" ]; then
                    terraform apply -input=false -auto-approve "$PLANFILE" || {
                        echo "Apply failed for $PLANFILE"
                    }
                else
                    terraform apply -var-file="$VAR_FILE" -input=false -auto-approve || {
                        echo "Apply failed for $PROJECT_DIR"
                    }
                fi
            done
EOF
