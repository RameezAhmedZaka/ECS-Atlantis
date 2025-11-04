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
    
    local env_prefix
    env_prefix=$(get_first_four_chars "$env")
    
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

        # Fallback: pick any .conf file
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
    
    local env_prefix
    env_prefix=$(get_first_four_chars "$env")
    
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

        # Fallback: pick any tfvars file
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
    
    if [ "$parent_dir" = "." ] || [ "$parent_dir" = "/" ]; then
        echo "$base_name"
    else
        echo "${parent_name}-${base_name}"
    fi
}

# Temporary files for storing env/config info
ENV_FILE=$(mktemp)
BACKEND_FILE=$(mktemp)
TFVARS_FILE=$(mktemp)

# First pass: discover Terraform projects recursively
echo "Searching for Terraform projects..."
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    [ -d "$project_dir" ] || continue
    if is_terraform_project "$project_dir"; then
        echo "Found project: $project_dir"
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -n "$env" ] || continue
            
            # Add to env file
            if ! grep -q "^$env$" "$ENV_FILE" 2>/dev/null; then
                echo "$env" >> "$ENV_FILE"
            fi
            
            # Discover configs
            backend_config=$(find_matching_backend_config "$project_dir" "$env")
            tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
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

# Second pass: generate project configurations
echo "Generating project configurations..."
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    [ -d "$project_dir" ] || continue
    if is_terraform_project "$project_dir"; then
        project_name=$(get_project_name "$project_dir")
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -z "$env" ] && continue
            env_path="$project_dir/env/${env}"
            [ -d "$env_path" ] || continue

            # Get config files
            project_backend_config=$(find_matching_backend_config "$project_dir" "$env")
            project_tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
            backend_config_to_use="${project_backend_config:-$(grep "^$env:" "$BACKEND_FILE" | cut -d: -f2-)}"
            tfvars_file_to_use="${project_tfvars_file:-$(grep "^$env:" "$TFVARS_FILE" | cut -d: -f2-)}"
            
            if [ -z "$backend_config_to_use" ] || [ -z "$tfvars_file_to_use" ]; then
                echo "Warning: Missing config files for $project_dir env $env"
                continue
            fi

            # Use paths as-is to avoid realpath issues
            project_relative_path="$project_dir"
            env_relative_path="$env_path"
            
            # Write project configuration
            {
            echo "  - name: ${project_name}-${env}"
            echo "    dir: $env_relative_path"
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
        done
    fi
done

# Generate workflows
cat >> atlantis.yaml <<EOF
workflows:
EOF

while IFS= read -r env; do
    [ -z "$env" ] && continue
    
    backend_config=$(grep "^$env:" "$BACKEND_FILE" | cut -d: -f2-)
    tfvars_file=$(grep "^$env:" "$TFVARS_FILE" | cut -d: -f2-)
    
    [ -z "$backend_config" ] || [ -z "$tfvars_file" ] && { echo "Skipping workflow for $env - missing config files"; continue; }

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
done < "$ENV_FILE"

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE"

echo "Generated atlantis.yaml successfully"
echo "Found projects:"
grep "name:" atlantis.yaml | sed 's/.*name: //'
