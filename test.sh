#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Start atlantis.yaml
cat > atlantis.yaml <<-EOF
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
        for config_file in "$env_path"/*.conf; do
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
        for config_file in "$env_path"/*.conf; do
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
        for tfvars_file in "$config_path"/*.tfvars; do
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
        for tfvars_file in "$config_path"/*.tfvars; do
            [ -f "$tfvars_file" ] && echo "config/$(basename "$tfvars_file")" && return 0
        done
    fi
    
    echo ""
}

# Collect all unique environments and their config patterns
declare -A all_environments
declare -A backend_configs
declare -A tfvars_files

# First pass: discover environments and their config files
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            environments=$(get_environments "$app_dir")
            while IFS= read -r env; do
                [ -n "$env" ] || continue
                all_environments["$env"]=1
                
                # Discover config files for this environment
                backend_config=$(find_matching_backend_config "$app_dir" "$env")
                tfvars_file=$(find_matching_tfvars_file "$app_dir" "$env")
                
                # Store the first valid config found for each environment
                if [ -n "$backend_config" ] && [ -z "${backend_configs[$env]:-}" ]; then
                    backend_configs["$env"]="$backend_config"
                    echo "Found backend config for $env: $backend_config"
                fi
                
                if [ -n "$tfvars_file" ] && [ -z "${tfvars_files[$env]:-}" ]; then
                    tfvars_files["$env"]="$tfvars_file"
                    echo "Found tfvars file for $env: $tfvars_file"
                fi
            done <<< "$environments"
        fi
    done
done

# Second pass: generate projects
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name="$(basename "$app_dir")"
            
            environments=$(get_environments "$app_dir")
            
            while IFS= read -r env; do
                [ -z "$env" ] && continue
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue

                # Get config files specific to this project
                project_backend_config=$(find_matching_backend_config "$app_dir" "$env")
                project_tfvars_file=$(find_matching_tfvars_file "$app_dir" "$env")
                
                # Use project-specific configs or fall back to global ones
                backend_config_to_use="${project_backend_config:-${backend_configs[$env]:-}}"
                tfvars_file_to_use="${project_tfvars_file:-${tfvars_files[$env]:-}}"
                
                if [ -z "$backend_config_to_use" ] || [ -z "$tfvars_file_to_use" ]; then
                    echo "Warning: Missing config files for $app_dir env $env"
                    echo "  Backend config: $backend_config_to_use"
                    echo "  TFVars file: $tfvars_file_to_use"
                    continue
                fi

                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: $env_path
    autoplan:
      enabled: true
      when_modified:
        - "../../*.tf"
        - "../../config/*.tfvars"
        - "../../env/*/*"
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
            done <<< "$environments"
        fi
    done
done

# Generate workflows for all found environments
cat >> atlantis.yaml << 'EOF'
workflows:
EOF

for env in "${!all_environments[@]}"; do
    backend_config="${backend_configs[$env]:-}"
    tfvars_file="${tfvars_files[$env]:-}"
    
    if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
        echo "Warning: Skipping workflow for $env - missing config files"
        continue
    fi
    
    cat >> atlantis.yaml << WORKFLOW_EOF
  ${env}_workflow:
    plan:
      steps:
        - run: |
            echo "Project: \$PROJECT_NAME"
            echo "Environment: $env"
            echo "Using backend config: $backend_config"
            echo "Using tfvars file: $tfvars_file"
            cd "\$(dirname "\$PROJECT_DIR")/../.."
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config=$backend_config -reconfigure -lock=false -input=false > /dev/null 2>&1
            terraform plan -var-file=$tfvars_file -lock-timeout=10m -out=\$PLANFILE
    apply:
      steps:
        - run: |
            echo "Project: \$PROJECT_NAME"
            echo "Environment: $env"
            cd "\$(dirname "\$PROJECT_DIR")/../.."
            terraform apply -auto-approve \$PLANFILE
WORKFLOW_EOF
done

echo "Generated atlantis.yaml with environments: ${!all_environments[@]}"