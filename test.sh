#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"
echo "Current directory: $(pwd)"

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
    echo "DEBUG: Checking if $dir is Terraform project"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Function to get all environments dynamically
get_environments() {
    local project_dir="$1"
    local envs_dir="$project_dir/env/"
    
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

# Fixed function to calculate relative path
get_relative_path() {
    local target="$1"
    local base="$2"
    
    # Convert both paths to absolute paths without cd'ing into them
    local abs_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
    local abs_base=$(cd "$base" && pwd)
    
    # Remove the base path from target path
    echo "${abs_target#$abs_base/}"
}

# Function to find matching backend config file
find_matching_backend_config() {
    local project_dir="$1"
    local env="$2"
    local env_path="$project_dir/env/${env}"
    
    local env_prefix=$(get_first_four_chars "$env")
    
    # Find all .conf files in the env directory
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            [ -f "$config_file" ] || continue
            local config_name=$(basename "$config_file" .conf)
            local config_prefix=$(get_first_four_chars "$config_name")
            
            if [ "$env_prefix" = "$config_prefix" ]; then
                echo "$(get_relative_path "$config_file" "$project_dir")"
                return 0
            fi
        done
    fi
    
    # Fallback: try to find any .conf file
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            [ -f "$config_file" ] && echo "$(get_relative_path "$config_file" "$project_dir")" && return 0
        done
    fi
    
    echo ""
}

# Function to find matching tfvars file
find_matching_tfvars_file() {
    local project_dir="$1"
    local env="$2"
    local config_path="$project_dir/config"
    
    local env_prefix=$(get_first_four_chars "$env")
    
    # Find all .tfvars files in the config directory
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            [ -f "$tfvars_file" ] || continue
            local tfvars_name=$(basename "$tfvars_file" .tfvars)
            local tfvars_prefix=$(get_first_four_chars "$tfvars_name")
            
            if [ "$env_prefix" = "$tfvars_prefix" ]; then
                echo "$(get_relative_path "$tfvars_file" "$project_dir")"
                return 0
            fi
        done
    fi
    
    # Fallback: try to find any .tfvars file
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            [ -f "$tfvars_file" ] && echo "$(get_relative_path "$tfvars_file" "$project_dir")" && return 0
        done
    fi
    
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

echo "Starting project discovery..."

# First pass: discover all Terraform projects recursively from root
echo "Searching for Terraform projects..."
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    if is_terraform_project "$project_dir"; then
        echo "Found valid project: $project_dir"
        
        environments=$(get_environments "$project_dir")
        echo "Environments found: $environments"
        echo "$environments" | while IFS= read -r env; do
            [ -n "$env" ] || continue
            echo "Processing environment: $env"
            
            # Add to environments list if not already present
            if ! grep -q "^$env$" "$ENV_FILE" 2>/dev/null; then
                echo "$env" >> "$ENV_FILE"
            fi
            
            # Discover config files for this environment
            backend_config=$(find_matching_backend_config "$project_dir" "$env")
            tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
            # Store configs if found and not already stored
            if [ -n "$backend_config" ] && ! grep -q "^$env:$backend_config$" "$BACKEND_FILE" 2>/dev/null; then
                echo "$env:$backend_config" >> "$BACKEND_FILE"
                echo "Found backend config for $env: $backend_config"
            fi
            
            if [ -n "$tfvars_file" ] && ! grep -q "^$env:$tfvars_file$" "$TFVARS_FILE" 2>/dev/null; then
                echo "$env:$tfvars_file" >> "$TFVARS_FILE"
                echo "Found tfvars file for $env: $tfvars_file"
            fi
        done
    else
        echo "Skipping $project_dir - not a valid Terraform project (missing required .tf files)"
    fi
done

# Alternative approach: find projects by looking for the required files
find . -type f -name "main.tf" | while read -r main_tf; do
    project_dir=$(dirname "$main_tf")
    
    # Skip if we already processed this project via env directory
    if [ -d "$project_dir/env" ] && is_terraform_project "$project_dir"; then
        continue
    fi
    
    # Check if this is a valid project
    if is_terraform_project "$project_dir"; then
        echo "Found project (via main.tf): $project_dir"
        
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
            if [ -n "$backend_config" ] && ! grep -q "^$env:$backend_config$" "$BACKEND_FILE" 2>/dev/null; then
                echo "$env:$backend_config" >> "$BACKEND_FILE"
                echo "Found backend config for $env: $backend_config"
            fi
            
            if [ -n "$tfvars_file" ] && ! grep -q "^$env:$tfvars_file$" "$TFVARS_FILE" 2>/dev/null; then
                echo "$env:$tfvars_file" >> "$TFVARS_FILE"
                echo "Found tfvars file for $env: $tfvars_file"
            fi
        done
    fi
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

# Second pass: generate projects for all discovered Terraform projects
echo "Generating project configurations..."

# Use a file to track project count since variables don't work across subshells
PROJECT_COUNT_FILE=$(mktemp)
echo "0" > "$PROJECT_COUNT_FILE"

# Find all projects with env directories
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    if is_terraform_project "$project_dir"; then
        project_name=$(get_project_name "$project_dir")
        
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -z "$env" ] && continue
            env_path="$project_dir/env/${env}"
            [ -d "$env_path" ] || continue

            echo "Generating config for: $project_dir - $env"

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
                echo "Warning: Missing config files for $project_dir env $env"
                echo "  Backend config: $backend_config_to_use"
                echo "  TFVars file: $tfvars_file_to_use"
                continue
            fi

            # Calculate relative paths - use project_dir instead of env_path for the main directory
            project_relative_path=$(get_relative_path "$project_dir" ".")
            
            # Write project configuration - dir points to project directory, not env directory
            {
            echo "  - name: ${project_name}-${env}"
            echo "    dir: $project_relative_path"
            echo "    autoplan:"
            echo "      enabled: true"
            echo "      when_modified:"
            echo "        - \"$project_relative_path/*.tf\""
            echo "        - \"$project_relative_path/config/*.tfvars\""
            echo "        - \"$project_relative_path/env/*/*\""
            echo "    terraform_version: v1.6.6"
            echo "    workflow: ${env}_workflow"
            echo "    apply_requirements:"
            echo "      - approved"
            echo "      - mergeable" 
            } >> atlantis.yaml
            
            echo "Added project: ${project_name}-${env}"
            # Update project count
            count=$(<"$PROJECT_COUNT_FILE")
            echo $((count + 1)) > "$PROJECT_COUNT_FILE"
        done
    fi
done

# Generate workflows for all found environments
cat >> atlantis.yaml <<EOF
workflows:
EOF

# Check if we have any environments
if [ ! -s "$ENV_FILE" ]; then
    echo "ERROR: No environments found!"
    echo "ENV_FILE contents:"
    cat "$ENV_FILE"
else
    echo "Processing environments from file:"
    cat "$ENV_FILE"
fi

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
    echo "            cd \"\$PROJECT_DIR\""
    echo "            rm -rf .terraform .terraform.lock.hcl"
    echo "            terraform init -backend-config=\"$backend_config\" -reconfigure -lock=false -input=false > /dev/null 2>&1"
    echo "            terraform plan -var-file=\"$tfvars_file\" -lock-timeout=10m -out=\$PLANFILE"
    echo "    apply:"
    echo "      steps:"
    echo "        - run: |"
    echo "            echo \"Project: \$PROJECT_NAME\""
    echo "            echo \"Environment: $env\""
    echo "            cd \"\$PROJECT_DIR\""
    echo "            terraform apply -auto-approve \$PLANFILE"
    } >> atlantis.yaml
    
    echo "Added workflow: ${env}_workflow"
done < "$ENV_FILE"

# Get final project count
PROJECT_COUNT=$(<"$PROJECT_COUNT_FILE")

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE" "$PROJECT_COUNT_FILE"

echo "Generated atlantis.yaml successfully"
echo "Total projects found: $PROJECT_COUNT"
echo "Final atlantis.yaml content:"
cat atlantis.yaml