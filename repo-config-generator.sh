#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

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

            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue

                echo "Found project: ${base_dir%/}-${app_name}-${env} at ${app_dir}"
                
                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: ${app_dir}
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/*/*"
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
            done
        fi
    done
done

# Create separate workflows for each environment with better error handling
cat >> atlantis.yaml << 'EOF'
workflows:
  production_workflow:
    plan:
      steps:
        - run: |
            echo "=== PRODUCTION WORKFLOW STARTED ==="
            echo "Project: $PROJECT_NAME"
            echo "Directory: $(pwd)"
            echo "Files in current directory:"
            ls -la
            echo "Files in env/production:"
            ls -la env/production/ || echo "env/production directory not found"
            echo "Files in config:"
            ls -la config/ || echo "config directory not found"
        - init:
            extra_args: [-backend-config=env/production/prod.conf]
        - run: echo "Init completed successfully"
        - plan:
            extra_args: [-var-file=config/production.tfvars, -lock-timeout=10m, -out=$PLANFILE]
        - run: echo "Plan completed successfully"
    apply:
      steps:
        - run: echo "=== PRODUCTION APPLY STARTED ==="
        - apply:
            extra_args: [-lock-timeout=10m]

  staging_workflow:
    plan:
      steps:
        - run: |
            echo "=== STAGING WORKFLOW STARTED ==="
            echo "Project: $PROJECT_NAME"
            echo "Files in env/staging:"
            ls -la env/staging/ || echo "env/staging directory not found"
        - init:
            extra_args: [-backend-config=env/staging/stage.conf]
        - plan:
            extra_args: [-var-file=config/stage.tfvars, -lock-timeout=10m, -out=$PLANFILE]
    apply:
      steps:
        - apply:
            extra_args: [-lock-timeout=10m]

  helia_workflow:
    plan:
      steps:
        - run: |
            echo "=== HELIA WORKFLOW STARTED ==="
            echo "Project: $PROJECT_NAME"
            echo "Files in env/helia:"
            ls -la env/helia/ || echo "env/helia directory not found"
        - init:
            extra_args: [-backend-config=env/helia/helia.conf]
        - plan:
            extra_args: [-var-file=config/helia.tfvars, -lock-timeout=10m, -out=$PLANFILE]
    apply:
      steps:
        - apply:
            extra_args: [-lock-timeout=10m]
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
#                          -lock=false  \
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