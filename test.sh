#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml"

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
        find "$envs_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
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

# Function to get project name based on directory path
get_project_name() {
    local project_dir="$1"
    local base_name=$(basename "$project_dir")
    local parent_dir=$(dirname "$project_dir")
    local parent_name=$(basename "$parent_dir")
    
    # Remove leading ./ if present
    parent_name="${parent_name#./}"
    
    # If we're at root level, just use the directory name
    if [ "$parent_dir" = "." ] || [ "$parent_dir" = "./" ]; then
        echo "$base_name"
    else
        echo "${parent_name}-${base_name}"
    fi
}

# Find all env directories and process their parent directories as projects
find . -type d -name env | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    echo "Checking directory: $project_dir" >&2
    
    if is_terraform_project "$project_dir"; then
        project_name=$(get_project_name "$project_dir")
        echo "Found Terraform project: $project_name in $project_dir" >&2
        
        environments=$(get_environments "$project_dir")
        if [ -n "$environments" ]; then
            echo "$environments" | while IFS= read -r env; do
                [ -z "$env" ] && continue
                
                backend_config=$(find_matching_backend_config "$project_dir" "$env")
                tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
                
                if [ -n "$backend_config" ] && [ -n "$tfvars_file" ]; then
                    echo "Adding project: ${project_name}-${env}" >&2
                    
                    # Write project configuration
                    cat >> atlantis.yaml <<PROJECT_CONFIG
  - name: ${project_name}-${env}
    dir: ${project_dir}/env/${env}
    autoplan:
      enabled: true
      when_modified:
        - "${project_dir}/*.tf"
        - "${project_dir}/config/*.tfvars"
        - "${project_dir}/env/*/*"
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable

PROJECT_CONFIG
                else
                    echo "Warning: Missing config files for $project_dir env $env (backend: $backend_config, tfvars: $tfvars_file)" >&2
                fi
            done
        else
            echo "Warning: No environments found in $project_dir/env/" >&2
        fi
    else
        echo "Skipping $project_dir - not a Terraform project" >&2
    fi
done

# Generate workflows section
cat >> atlantis.yaml <<EOF
workflows:
EOF

# Get unique environments from the generated projects
if [ -f atlantis.yaml ]; then
    grep "workflow:" atlantis.yaml | awk '{print $2}' | sort -u | while read -r env; do
        # Remove any trailing characters after workflow name
        env=$(echo "$env" | sed 's/_workflow$//')
        if [ -n "$env" ]; then
            echo "Generating workflow for: $env" >&2
            cat >> atlantis.yaml <<WORKFLOW_CONFIG
  ${env}_workflow:
    plan:
      steps:
        - run: |
            echo "Project: \$PROJECT_NAME"
            echo "Environment: $env"
            cd "\$(dirname "\$PROJECT_DIR")/.."
            rm -rf .terraform .terraform.lock.hcl
            terraform init -reconfigure -lock=false -input=false
            terraform plan -lock-timeout=10m -out=\$PLANFILE
    apply:
      steps:
        - run: |
            echo "Project: \$PROJECT_NAME"
            echo "Environment: $env"
            cd "\$(dirname "\$PROJECT_DIR")/.."
            terraform apply -auto-approve \$PLANFILE

WORKFLOW_CONFIG
        fi
    done
fi

echo "Generated atlantis.yaml successfully"
echo "Final atlantis.yaml contents:" >&2
cat atlantis.yaml >&2