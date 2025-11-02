# #!/bin/bash
# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: false
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
#     dir: .
#     autoplan:
#       enabled: true
#       when_modified:
#         - "${base_dir}${app_name}/*.tf"
#         - "${base_dir}${app_name}/config/*.tfvars"
#         - "${base_dir}${app_name}/env/*/*"
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

# # Workflows using terraform -chdir and correct plan file paths
# cat >> atlantis.yaml << 'EOF'
# workflows:
#   production_workflow:
#     plan:
#       steps:
#         - run: |
#             APP_DIR=$(echo "$PROJECT_NAME" | awk -F'-' '{print $1"/"$2}')
#             PLANFILE="tfplan"  
#             echo "Planning project: $PROJECT_NAME in $APP_DIR"
#             rm -rf "$APP_DIR/.terraform" "$APP_DIR/.terraform.lock.hcl"
#             terraform -chdir="$APP_DIR" init -backend-config=env/production/prod.conf -reconfigure -input=false
#             terraform -chdir="$APP_DIR" plan -var-file=config/production.tfvars -lock-timeout=10m -out="$PLANFILE"
#     apply:
#       steps:
#         - run: |
#             APP_DIR=$(echo "$PROJECT_NAME" | awk -F'-' '{print $1"/"$2}')
#             PLANFILE="tfplan"
#             echo "Applying project: $PROJECT_NAME in $APP_DIR"
#             timeout 600 terraform -chdir="$APP_DIR" apply -input=false -auto-approve "$PLANFILE"

#   staging_workflow:
#     plan:
#       steps:
#         - run: |
#             APP_DIR=$(echo "$PROJECT_NAME" | awk -F'-' '{print $1"/"$2}')
#             PLANFILE="tfplan"
#             echo "Planning project: $PROJECT_NAME in $APP_DIR"
#             rm -rf "$APP_DIR/.terraform" "$APP_DIR/.terraform.lock.hcl"
#             terraform -chdir="$APP_DIR" init -backend-config=env/staging/stage.conf -reconfigure -input=false
#             terraform -chdir="$APP_DIR" plan -var-file=config/stage.tfvars -lock-timeout=10m -out="$PLANFILE"
#     apply:
#       steps:
#         - run: |
#             APP_DIR=$(echo "$PROJECT_NAME" | awk -F'-' '{print $1"/"$2}')
#             PLANFILE="tfplan"
#             echo "Applying project: $PROJECT_NAME in $APP_DIR"
#             timeout 600 terraform -chdir="$APP_DIR" apply -input=false -auto-approve "$PLANFILE"

#   helia_workflow:
#     plan:
#       steps:
#         - run: |
#             APP_DIR=$(echo "$PROJECT_NAME" | awk -F'-' '{print $1"/"$2}')
#             PLANFILE="tfplan"
#             echo "Planning project: $PROJECT_NAME in $APP_DIR"
#             rm -rf "$APP_DIR/.terraform" "$APP_DIR/.terraform.lock.hcl"
#             terraform -chdir="$APP_DIR" init -backend-config=env/helia/helia.conf -reconfigure -input=false
#             terraform -chdir="$APP_DIR" plan -var-file=config/helia.tfvars -lock-timeout=10m -out="$PLANFILE"
#     apply:
#       steps:
#         - run: |
#             APP_DIR=$(echo "$PROJECT_NAME" | awk -F'-' '{print $1"/"$2}')
#             PLANFILE="tfplan"
#             echo "Applying project: $PROJECT_NAME in $APP_DIR"
#             timeout 600 terraform -chdir="$APP_DIR" apply -input=false -auto-approve "$PLANFILE"
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






#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Create base atlantis.yaml with document start
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Function to check if directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Function to get environments for an app
get_environments() {
    local app_dir="$1"
    local envs=()
    declare -A env_map=( ["production"]="production" ["staging"]="stage" ["helia"]="helia" )
    for env in "${!env_map[@]}"; do
        tfvars_file="$app_dir/config/${env_map[$env]}.tfvars"
        env_dir="$app_dir/env/$env"
        if [ -f "$tfvars_file" ] && [ -d "$env_dir" ]; then
            envs+=("$env")
        fi
    done
    echo "${envs[@]}"
}

# Array to track project names
declare -a project_names=()

# Loop through all top-level directories (e.g., application, db, network, etc.)
for base_dir in */; do
    [ -d "$base_dir" ] || continue

    # Loop through each subdirectory (e.g., application/app1, db/mysql)
    for sub_dir in "$base_dir"*/; do
        [ -d "$sub_dir" ] || continue

        if is_terraform_project "$sub_dir"; then
            app_name="$(basename "$sub_dir")"
            envs=$(get_environments "$sub_dir")

            if [ -z "$envs" ]; then
                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-default
    dir: $sub_dir
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
                project_names+=("${base_dir%/}-${app_name}-default")
            else
                for env in $envs; do
                    cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: $sub_dir
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/$env/*"
    terraform_version: v1.6.6
    workflow: multi_env_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                    project_names+=("${base_dir%/}-${app_name}-${env}")
                done
            fi
        fi
    done
done

echo "Total projects configured: ${#project_names[@]}"
echo "Project names: ${project_names[*]}"

# Workflows section (single-quoted EOF to preserve $PROJECT_NAME at runtime)
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
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
            esac

            echo "Planning for environment: $ENV"
            echo "Using backend config: $BACKEND_CONFIG"
            echo "Using var file: $VAR_FILE"
            echo "Destroy flag: $DESTROY_FLAG"

            cd "$PROJECT_DIR"

            if [ -f "$BACKEND_CONFIG" ]; then
              timeout 300 terraform init -lock=false\
                -backend-config="$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure
            fi

            if [ -f "$VAR_FILE" ]; then
              timeout 300 terraform plan -lock=false \
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
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
            esac

            echo "Applying for environment: $ENV"

            cd "$PROJECT_DIR"

            if [ -f "$BACKEND_CONFIG" ]; then
              timeout 300 terraform init -lock=false\
                -backend-config="$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure > /dev/null 2>&1
            fi

            # Apply the plan if it exists, otherwise do a raw apply with var-file
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
