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
            while IFS= read -r env; do
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
            done <<< "$environments"
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
            
            while IFS= read -r env; do
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

# Process each environment from file
while IFS= read -r env; do
    [ -z "$env" ] && continue
    
    backend_config=$(get_backend_config_for_env "$env")
    tfvars_file=$(get_tfvars_file_for_env "$env")
    
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
done < "$ENV_FILE"

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE"

echo "Generated atlantis.yaml successfully"