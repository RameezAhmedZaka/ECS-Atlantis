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

# Debug function that writes to stderr
debug() {
    echo "$@" >&2
}

debug "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"
debug "Current directory: $(pwd)"
debug "Directory contents:"
ls -la >&2

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
    debug "Checking if $dir is a Terraform project..."
    
    if [ -f "$dir/main.tf" ]; then
        debug "  ✓ Found main.tf"
    else
        debug "  ✗ Missing main.tf"
        return 1
    fi
    
    if [ -f "$dir/variables.tf" ]; then
        debug "  ✓ Found variables.tf"
    else
        debug "  ✗ Missing variables.tf"
        return 1
    fi
    
    if [ -f "$dir/providers.tf" ]; then
        debug "  ✓ Found providers.tf"
    else
        debug "  ✗ Missing providers.tf"
        return 1
    fi
    
    debug "  ✓ $dir is a valid Terraform project"
    return 0
}

# Function to get all environments dynamically
get_environments() {
    local project_dir="$1"
    local envs_dir="$project_dir/env/"
    
    debug "Looking for environments in: $envs_dir"
    
    if [ -d "$envs_dir" ]; then
        local envs=$(find "$envs_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort)
        debug "Found environments: $envs"
        echo "$envs"
    else
        debug "No env directory found at: $envs_dir"
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
    local project_dir="$1"
    local env="$2"
    local env_path="$project_dir/env/${env}"
    
    debug "Looking for backend config in: $env_path"
    local env_prefix=$(get_first_four_chars "$env")
    debug "Environment prefix: $env_prefix"
    
    # Find all .conf files in the env directory
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            [ -f "$config_file" ] || continue
            local config_name=$(basename "$config_file" .conf)
            local config_prefix=$(get_first_four_chars "$config_name")
            debug "Checking config file: $config_file (prefix: $config_prefix)"
            
            if [ "$env_prefix" = "$config_prefix" ]; then
                debug "✓ Found matching backend config: env/${env}/$(basename "$config_file")"
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
    
    debug "✗ No backend config found for $env"
    echo ""
}

# Function to find matching tfvars file
find_matching_tfvars_file() {
    local project_dir="$1"
    local env="$2"
    local config_path="$project_dir/config"
    
    debug "Looking for tfvars in: $config_path"
    local env_prefix=$(get_first_four_chars "$env")
    debug "Environment prefix: $env_prefix"
    
    # Find all .tfvars files in the config directory
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            [ -f "$tfvars_file" ] || continue
            local tfvars_name=$(basename "$tfvars_file" .tfvars)
            local tfvars_prefix=$(get_first_four_chars "$tfvars_name")
            debug "Checking tfvars file: $tfvars_file (prefix: $tfvars_prefix)"
            
            if [ "$env_prefix" = "$tfvars_prefix" ]; then
                debug "✓ Found matching tfvars: config/$(basename "$tfvars_file")"
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
    
    debug "✗ No tfvars file found for $env"
    echo ""
}

# Function to get project name based on directory path
get_project_name() {
    local project_dir="$1"
    local base_name=$(basename "$project_dir")
    local parent_dir=$(dirname "$project_dir")
    local parent_name=$(basename "$parent_dir")
    
    # If we're at root level, just use the directory name
    if [ "$parent_dir" = "." ] || [ "$parent_dir" = "/" ]; then
        echo "$base_name"
    else
        echo "${parent_name}-${base_name}"
    fi
}

# Use files to store environments and configs
ENV_FILE=$(mktemp)
BACKEND_FILE=$(mktemp)
TFVARS_FILE=$(mktemp)

debug "=== PHASE 1: Discovering Terraform projects ==="

# Method 1: Find projects by env directories
debug "Method 1: Searching for env directories..."
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    debug "Found env directory at: $env_dir"
    debug "Project directory would be: $project_dir"
    
    if is_terraform_project "$project_dir"; then
        debug "✓ Valid Terraform project found: $project_dir"
        
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -n "$env" ] || continue
            
            # Add to environments list if not already present
            if ! grep -q "^$env$" "$ENV_FILE" 2>/dev/null; then
                echo "$env" >> "$ENV_FILE"
            fi
            
            # Discover config files for this environment
            backend_config=$(find_matching_backend_config "$project_dir" "$env")
            tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
            # Store configs if found and not already stored
            if [ -n "$backend_config" ] && ! grep -q "^$env:" "$BACKEND_FILE" 2>/dev/null; then
                echo "$env:$backend_config" >> "$BACKEND_FILE"
            fi
            
            if [ -n "$tfvars_file" ] && ! grep -q "^$env:" "$TFVARS_FILE" 2>/dev/null; then
                echo "$env:$tfvars_file" >> "$TFVARS_FILE"
            fi
        done
    else
        debug "✗ Not a valid Terraform project: $project_dir"
    fi
    debug "---"
done

# Method 2: Find projects by main.tf files
debug "Method 2: Searching for main.tf files..."
find . -type f -name "main.tf" | while read -r main_tf; do
    project_dir=$(dirname "$main_tf")
    debug "Found main.tf at: $main_tf"
    debug "Project directory would be: $project_dir"
    
    # Skip if we already processed this project via env directory
    if [ -d "$project_dir/env" ] && is_terraform_project "$project_dir"; then
        debug "Skipping - already processed via env directory"
        continue
    fi
    
    # Check if this is a valid project
    if is_terraform_project "$project_dir"; then
        debug "✓ Valid Terraform project found: $project_dir"
        
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -n "$env" ] || continue
            
            # Add to environments list if not already present
            if ! grep -q "^$env$" "$ENV_FILE" 2>/dev/null; then
                echo "$env" >> "$ENV_FILE"
            fi
            
            # Discover config files for this environment
            backend_config=$(find_matching_backend_config "$project_dir" "$env")
            tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
            # Store configs if found and not already stored
            if [ -n "$backend_config" ] && ! grep -q "^$env:" "$BACKEND_FILE" 2>/dev/null; then
                echo "$env:$backend_config" >> "$BACKEND_FILE"
            fi
            
            if [ -n "$tfvars_file" ] && ! grep -q "^$env:" "$TFVARS_FILE" 2>/dev/null; then
                echo "$env:$tfvars_file" >> "$TFVARS_FILE"
            fi
        done
    else
        debug "✗ Not a valid Terraform project: $project_dir"
    fi
    debug "---"
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

debug "=== PHASE 2: Generating project configurations ==="

# Generate projects for all discovered Terraform projects
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    if is_terraform_project "$project_dir"; then
        project_name=$(get_project_name "$project_dir")
        debug "Generating configuration for project: $project_name in $project_dir"
        
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -z "$env" ] && continue
            env_path="$project_dir/env/${env}"
            [ -d "$env_path" ] || continue

            debug "Processing environment: $env"
            
            # Get config files specific to this project
            project_backend_config=$(find_matching_backend_config "$project_dir" "$env")
            project_tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
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
                debug "Warning: Missing config files for $project_dir env $env"
                debug "  Backend config: $backend_config_to_use"
                debug "  TFVars file: $tfvars_file_to_use"
                continue
            fi

            debug "✓ Generating Atlantis config for: $project_name-$env"
            debug "  Directory: $project_dir/env/$env"
            debug "  Backend config: $backend_config_to_use"
            debug "  TFVars: $tfvars_file_to_use"

            # Write project configuration (to stdout, which goes to atlantis.yaml)
            {
            echo "  - name: ${project_name}-${env}"
            echo "    dir: $project_dir/env/${env}"
            echo "    autoplan:"
            echo "      enabled: true"
            echo "      when_modified:"
            echo "        - \"$project_dir/*.tf\""
            echo "        - \"$project_dir/config/*.tfvars\""
            echo "        - \"$project_dir/env/*/*\""
            echo "    terraform_version: v1.6.6"
            echo "    workflow: ${env}_workflow"
            echo "    apply_requirements:"
            echo "      - approved"
            echo "      - mergeable"
            } >> atlantis.yaml
        done
    fi
done

debug "=== PHASE 3: Generating workflows ==="

# Generate workflows for all found environments
cat >> atlantis.yaml <<EOF
workflows:
EOF

# Process each environment from file
if [ -s "$ENV_FILE" ]; then
    debug "Found environments: $(cat "$ENV_FILE" | tr '\n' ' ')"
    
    while IFS= read -r env; do
        [ -z "$env" ] && continue
        
        backend_config=$(get_backend_config_for_env "$env")
        tfvars_file=$(get_tfvars_file_for_env "$env")
        
        if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
            debug "Warning: Skipping workflow for $env - missing config files"
            continue
        fi
        
        debug "Generating workflow for: $env"
        
        # Write workflow configuration (to stdout, which goes to atlantis.yaml)
        {
        echo "  ${env}_workflow:"
        echo "    plan:"
        echo "      steps:"
        echo "        - run: |"
        echo "            echo \"Project: \$PROJECT_NAME\""
        echo "            echo \"Environment: $env\""
        echo "            echo \"Using backend config: $backend_config\""
        echo "            echo \"Using tfvars file: $tfvars_file\""
        echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/..\""
        echo "            rm -rf .terraform .terraform.lock.hcl"
        echo "            terraform init -backend-config=\"$backend_config\" -reconfigure -lock=false -input=false > /dev/null 2>&1"
        echo "            terraform plan -var-file=\"$tfvars_file\" -lock-timeout=10m -out=\$PLANFILE"
        echo "    apply:"
        echo "      steps:"
        echo "        - run: |"
        echo "            echo \"Project: \$PROJECT_NAME\""
        echo "            echo \"Environment: $env\""
        echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/..\""
        echo "            terraform apply -auto-approve \$PLANFILE"
        } >> atlantis.yaml
    done < "$ENV_FILE"
else
    debug "No environments found!"
fi

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE"

debug "=== GENERATION COMPLETE ==="
debug "Generated atlantis.yaml successfully"

# Show the final result (to stderr)
debug "Final atlantis.yaml contents:"
cat atlantis.yaml >&2