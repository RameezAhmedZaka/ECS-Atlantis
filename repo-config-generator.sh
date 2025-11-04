# #!/bin/bash
# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: true
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

# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Compare changes against main branch
# git fetch origin main >/dev/null 2>&1 || true
# CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")

# # Function to check if any files in a directory changed
# has_changes() {
#     local dir="$1"
#     if [ -z "$CHANGED_FILES" ]; then
#         return 0  # If we can't detect changes, include all projects
#     fi
#     echo "$CHANGED_FILES" | grep -q "^$dir"
# }

# # Function to check if main Terraform files changed
# main_files_changed() {
#     if [ -z "$CHANGED_FILES" ]; then
#         return 1  # If we can't detect changes, assume main files didn't change
#     fi
#     echo "$CHANGED_FILES" | grep -q -E "(\.tf$|\.tfvars$)" | grep -v "/env/"
# }

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: false
# parallel_apply: false
# projects:
# EOF

# # Function to check if a directory is a Terraform project
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
            
#             # Check if main files changed (triggers all environments)
#             main_changed=$(main_files_changed && echo "true" || echo "false")
            
#             # Add project entries for each environment
#             for env in helia staging production; do
#                 env_path="${app_dir}env/${env}"
#                 [ -d "$env_path" ] || continue
                
#                 # Only include this environment if:
#                 # 1. Main files changed, OR
#                 # 2. This specific environment directory changed
#                 if [ "$main_changed" = "true" ] || has_changes "$env_path"; then
#                     cat >> atlantis.yaml << PROJECT_EOF
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
#                 else
#                     echo "Skipping ${base_dir%/}-${app_name}-${env} - no changes detected"
#                 fi
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
#             terraform workspace select "prod-pr-$PULL_NUM" || terraform workspace new "prod-pr-$PULL_NUM"
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
#             terraform workspace select "stage-pr-$PULL_NUM" || terraform workspace new "stage-pr-$PULL_NUM"
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
#             terraform workspace select "helia-pr-$PULL_NUM" || terraform workspace new "helia-pr-$PULL_NUM"
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

# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Compare changes against main branch
# git fetch origin main >/dev/null 2>&1 || true
# CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")

# # Function to check if any files in a directory changed
# has_changes() {
#     local dir="$1"
#     if [ -z "$CHANGED_FILES" ]; then
#         return 0  # If we can't detect changes, include all projects
#     fi
#     echo "$CHANGED_FILES" | grep -q "^$dir"
# }

# # Function to check if main Terraform files changed
# main_files_changed() {
#     if [ -z "$CHANGED_FILES" ]; then
#         return 1  # If we can't detect changes, assume main files didn't change
#     fi
#     echo "$CHANGED_FILES" | grep -q -E "(\.tf$|\.tfvars$)" | grep -v "/env/"
# }

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: false
# parallel_apply: false
# projects:
# EOF

# # Function to check if a directory is a Terraform project
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
            
#             # Check if main files changed (triggers all environments)
#             main_changed=$(main_files_changed && echo "true" || echo "false")
            
#             # Add project entries for each environment
#             for env in helia staging production; do
#                 env_path="${app_dir}env/${env}"
#                 [ -d "$env_path" ] || continue
                
#                 # Only include this environment if:
#                 # 1. Main files changed, OR
#                 # 2. This specific environment directory changed
#                 if [ "$main_changed" = "true" ] || has_changes "$env_path"; then
#                     cat >> atlantis.yaml << PROJECT_EOF
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
#                 else
#                     echo "Skipping ${base_dir%/}-${app_name}-${env} - no changes detected"
#                 fi
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
cat > atlantis.yaml <<EOF
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

# Function to get all environments dynamically
get_environments() {
    local app_dir="$1"
    local envs_dir="${app_dir}env/"
    
    if [ -d "$envs_dir" ]; then
        find "$envs_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
    else
        echo ""
    fi
}

# Function to get first 4 characters (or full name if shorter)
get_first_four_chars() {
    local name="$1"
    echo "${name:0:4}" | tr '[:upper:]' '[:lower:]'
}

# Function to find matching backend config file
find_matching_backend_config() {
    local app_dir="$1"
    local env="$2"
    local env_path="${app_dir}env/${env}"
    
    local env_prefix=$(get_first_four_chars "$env")
    
    # Find all .conf files in the env directory
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            [ -f "$config_file" ] || continue
            local config_name=$(basename "$config_file" .conf)
            local config_prefix=$(get_first_four_chars "$config_name")
            
            if [ "$env_prefix" = "$config_prefix" ]; then
                echo "env/${env}/$(basename "$config_file")"
                return 0
            fi
        done
    fi
    
    # Fallback: try to find any .conf file
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            [ -f "$config_file" ] && echo "env/${env}/$(basename "$config_file")" && return 0
        done
    fi
    
    echo ""
}

# Function to find matching tfvars file
find_matching_tfvars_file() {
    local app_dir="$1"
    local env="$2"
    local config_path="${app_dir}config"
    
    local env_prefix=$(get_first_four_chars "$env")
    
    # Find all .tfvars files in the config directory
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            [ -f "$tfvars_file" ] || continue
            local tfvars_name=$(basename "$tfvars_file" .tfvars)
            local tfvars_prefix=$(get_first_four_chars "$tfvars_name")
            
            if [ "$env_prefix" = "$tfvars_prefix" ]; then
                echo "config/$(basename "$tfvars_file")"
                return 0
            fi
        done
    fi
    
    # Fallback: try to find any .tfvars file
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            [ -f "$tfvars_file" ] && echo "config/$(basename "$tfvars_file")" && return 0
        done
    fi
    
    echo ""
}

# Use files to store environments and configs
ENV_FILE=$(mktemp)
BACKEND_FILE=$(mktemp)
TFVARS_FILE=$(mktemp)

# First pass: discover environments and their config files
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            environments=$(get_environments "$app_dir")
            echo "$environments" | while IFS= read -r env; do
                [ -n "$env" ] || continue
                
                # Add to environments list if not already present
                if ! grep -q "^$env$" "$ENV_FILE" 2>/dev/null; then
                    echo "$env" >> "$ENV_FILE"
                fi
                
                # Discover config files for this environment
                backend_config=$(find_matching_backend_config "$app_dir" "$env")
                tfvars_file=$(find_matching_tfvars_file "$app_dir" "$env")
                
                # Store configs if found and not already stored
                if [ -n "$backend_config" ] && ! grep -q "^$env:" "$BACKEND_FILE" 2>/dev/null; then
                    echo "$env:$backend_config" >> "$BACKEND_FILE"
                    echo "Found backend config for $env: $backend_config"
                fi
                
                if [ -n "$tfvars_file" ] && ! grep -q "^$env:" "$TFVARS_FILE" 2>/dev/null; then
                    echo "$env:$tfvars_file" >> "$TFVARS_FILE"
                    echo "Found tfvars file for $env: $tfvars_file"
                fi
            done
        fi
    done
done

# Function to get config from stored files
get_backend_config_for_env() {
    local env="$1"
    grep "^${env}:" "$BACKEND_FILE" 2>/dev/null | cut -d: -f2- || echo ""
}

get_tfvars_file_for_env() {
    local env="$1"
    grep "^${env}:" "$TFVARS_FILE" 2>/dev/null | cut -d: -f2- || echo ""
}

# Second pass: generate projects
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name="$(basename "$app_dir")"
            
            environments=$(get_environments "$app_dir")
            echo "$environments" | while IFS= read -r env; do
                [ -z "$env" ] && continue
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue

                # Get config files specific to this project
                project_backend_config=$(find_matching_backend_config "$app_dir" "$env")
                project_tfvars_file=$(find_matching_tfvars_file "$app_dir" "$env")
                
                # Use project-specific configs or fall back to stored ones
                backend_config_to_use="$project_backend_config"
                tfvars_file_to_use="$project_tfvars_file"
                
                if [ -z "$backend_config_to_use" ]; then
                    backend_config_to_use=$(get_backend_config_for_env "$env")
                fi
                
                if [ -z "$tfvars_file_to_use" ]; then
                    tfvars_file_to_use=$(get_tfvars_file_for_env "$env")
                fi
                
                if [ -z "$backend_config_to_use" ] || [ -z "$tfvars_file_to_use" ]; then
                    echo "Warning: Missing config files for $app_dir env $env"
                    echo "  Backend config: $backend_config_to_use"
                    echo "  TFVars file: $tfvars_file_to_use"
                    continue
                fi

                # Write project configuration
                {
                echo "  - name: ${base_dir%/}-${app_name}-${env}"
                echo "    dir: $env_path"
                echo "    autoplan:"
                echo "      enabled: true"
                echo "      when_modified:"
                echo "        - \"../../*.tf\""
                echo "        - \"../../config/*.tfvars\""
                echo "        - \"../../env/*/*\""
                echo "    terraform_version: v1.6.6"
                echo "    workflow: ${env}_workflow"
                echo "    apply_requirements:"
                echo "      - approved"
                echo "      - mergeable"
                } >> atlantis.yaml
            done
        fi
    done
done

# Generate workflows for all found environments
cat >> atlantis.yaml <<EOF
workflows:
EOF

# Process each environment from file
while IFS= read -r env; do
    [ -z "$env" ] && continue
    
    backend_config=$(get_backend_config_for_env "$env")
    tfvars_file=$(get_tfvars_file_for_env "$env")
    
    if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
        echo "Warning: Skipping workflow for $env - missing config files"
        continue
    fi
    
    # Write workflow configuration
    {
    echo "  ${env}_workflow:"
    echo "    plan:"
    echo "      steps:"
    echo "        - run: |"
    echo "            echo \"Project: \$PROJECT_NAME\""
    echo "            echo \"Environment: $env\""
    echo "            echo \"Using backend config: $backend_config\""
    echo "            echo \"Using tfvars file: $tfvars_file\""
    echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/../..\""
    echo "            rm -rf .terraform .terraform.lock.hcl"
    echo "            terraform init -backend-config=$backend_config -reconfigure -lock=false -input=false > /dev/null 2>&1"
    echo "            terraform plan -var-file=$tfvars_file -lock-timeout=10m -out=\$PLANFILE"
    echo "    apply:"
    echo "      steps:"
    echo "        - run: |"
    echo "            echo \"Project: \$PROJECT_NAME\""
    echo "            echo \"Environment: $env\""
    echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/../..\""
    echo "            terraform apply -auto-approve \$PLANFILE"
    } >> atlantis.yaml
done < "$ENV_FILE"

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE"

echo "Generated atlantis.yaml successfully"