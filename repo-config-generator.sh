#!/bin/bash
set -euo pipefail
trap '' PIPE 

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
                echo "$config_file"
                return 0
            fi
        done
    fi
    
    # Fallback: try to find any .conf file
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            [ -f "$config_file" ] && echo "$config_file" && return 0
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
                echo "$tfvars_file"
                return 0
            fi
        done
    fi
    
    # Fallback: try to find any .tfvars file
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            [ -f "$tfvars_file" ] && echo "$tfvars_file" && return 0
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

# Function to calculate relative path from env dir to project root
get_relative_path_to_root() {
    local env_dir="$1"
    local project_dir="$2"
    
    # Count how many levels deep the env dir is from project dir
    local levels_deep=$(echo "$env_dir" | sed "s|$project_dir/||" | tr -cd '/' | wc -c)
    levels_deep=$((levels_deep + 1))  # Add 1 for the env directory itself
    
    # Generate the relative path (e.g., "../../" for 2 levels deep)
    if [ $levels_deep -eq 0 ]; then
        echo "."
    else
        printf '../%.0s' $(seq 1 $levels_deep) | sed 's/.$//'
    fi
}

# Use files to store environments, configs, and project info
ENV_FILE=$(mktemp)
BACKEND_FILE=$(mktemp)
TFVARS_FILE=$(mktemp)
PROJECT_INFO_FILE=$(mktemp)

# First pass: discover all Terraform projects recursively from root
echo "Searching for Terraform projects..."
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    if is_terraform_project "$project_dir"; then
        echo "Found project: $project_dir"
        
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

            # Calculate relative path from env directory to project root
            relative_to_root=$(get_relative_path_to_root "$env_path" "$project_dir")
            
            # Store project info for workflow generation
            echo "$env:$project_dir:$relative_to_root" >> "$PROJECT_INFO_FILE"
            
            # Write project configuration - dir points to env directory
            {
            echo "  - name: ${project_name}-${env}"
            echo "    dir: $env_path"
            echo "    autoplan:"
            echo "      enabled: true"
            echo "      when_modified:"
            echo "        - \"${relative_to_root}/*.tf\""
            echo "        - \"${relative_to_root}/config/*.tfvars\""
            echo "        - \"${relative_to_root}/env/*/*\""
            echo "    terraform_version: v1.6.6"
            echo "    workflow: ${env}_workflow"
            echo "    apply_requirements:"
            echo "      - approved"
            echo "      - mergeable"
            } >> atlantis.yaml
        done
    fi
done

# Generate workflows for all found environments based on actual projects
cat >> atlantis.yaml <<EOF
workflows:
EOF

# Get unique environments from PROJECT_INFO_FILE
awk -F: '{print $1}' "$PROJECT_INFO_FILE" | sort -u | while read -r env; do
    [ -z "$env" ] && continue

    backend_config=$(get_backend_config_for_env "$env")
    tfvars_file=$(get_tfvars_file_for_env "$env")

    if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
        echo "Warning: Skipping workflow for $env - missing config files"
        continue
    fi

    backend_config_file=$(basename "$backend_config")
    tfvars_config_file=$(basename "$tfvars_file")

    # Get a sample relative path for this environment
    sample_relative_path=$(grep "^${env}:" "$PROJECT_INFO_FILE" | head -1 | cut -d: -f3)
    if [ -z "$sample_relative_path" ]; then
        sample_relative_path="../.."  # Default fallback
    fi

    # Write workflow configuration
{
    echo "  ${env}_workflow:"
    echo "    plan:"
    echo "      steps:"
    echo "        - run: |"
    echo "            echo \"Project: \$PROJECT_NAME\""
    echo "            echo \"Environment: $env\""
    echo "            echo \"Using backend config: $backend_config_file\""
    echo "            echo \"Using tfvars file: $tfvars_config_file\""
    echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/$sample_relative_path\""
    echo "            rm -rf .terraform .terraform.lock.hcl"
    echo "            terraform init -backend-config=\"env/$env/$backend_config_file\" -reconfigure -lock=false -input=false > /dev/null 2>&1"
    echo "            terraform plan -compact-warnings -var-file=\"config/$tfvars_config_file\" -lock-timeout=10m -out=\$PLANFILE > /dev/null 2>&1"
    echo "            terraform show \$PLANFILE"
    echo "    apply:"
    echo "      steps:"
    echo "        - run: |"
    echo "            echo \"Project: \$PROJECT_NAME\""
    echo "            echo \"Environment: $env\""
    echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/$sample_relative_path\""
    echo "            terraform apply -auto-approve \$PLANFILE"
} >> atlantis.yaml
done

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE" "$PROJECT_INFO_FILE"

echo "Generated atlantis.yaml successfully"
