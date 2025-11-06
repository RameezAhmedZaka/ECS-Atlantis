#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Start atlantis.yaml
cat > atlantis.yaml <<EOF
---
version: 3
automerge: true
parallel_plan: true
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

# Find all Terraform projects with env directories
echo "Searching for Terraform projects..."
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    if is_terraform_project "$project_dir"; then
        echo "Found project: $project_dir"
        project_name=$(get_project_name "$project_dir")
        
        environments=$(get_environments "$project_dir")
        echo "$environments" | while IFS= read -r env; do
            [ -z "$env" ] && continue
            
            backend_config=$(find_matching_backend_config "$project_dir" "$env")
            tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
            
            if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
                echo "Warning: Missing config files for $project_dir env $env"
                echo "  Backend config: $backend_config"
                echo "  TFVars file: $tfvars_file"
                continue
            fi

            # Write project configuration
            {
            echo "  - name: ${project_name}-${env}"
            echo "    dir: $project_dir"
            echo "    autoplan:"
            echo "      enabled: true"
            echo "      when_modified:"
            echo "        - \"*.tf\""
            echo "        - \"$project_dir/*.tf\""
            echo "        - \"$project_dir/config/*.tfvars\""
            echo "        - \"$project_dir/env/*/*\""
            echo "    terraform_version: v1.6.6"
            echo "    apply_requirements:"
            echo "      - approved"
            echo "      - mergeable"
            } >> atlantis.yaml
            
            # Add environment-specific workflow with proper backend config
            {
            echo "workflows:"
            echo "  ${project_name}-${env}:"
            echo "    plan:"
            echo "      steps:"
            echo "        - run: rm -rf .terraform .terraform.lock.hcl"
            echo "        - init:"
            echo "            extra_args:"
            echo "              - -backend-config=$backend_config"
            echo "              - -reconfigure"
            echo "        - plan:"
            echo "            extra_args:"
            echo "              - -var-file=$tfvars_file"
            echo "              - -lock-timeout=10m"
            echo "            extra_args: []"
            echo "    apply:"
            echo "      steps:"
            echo "        - apply:"
            echo "            extra_args:"
            echo "              - -auto-approve"
            } >> atlantis.yaml
        done
    fi
done

echo "Generated atlantis.yaml successfully"
echo "Found projects:"
grep "name:" atlantis.yaml | sed 's/.*name: //'