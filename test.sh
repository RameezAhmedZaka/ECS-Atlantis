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
    if [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]; then
        return 0
    else
        return 1
    fi
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
            if [ -f "$config_file" ]; then
                local config_name=$(basename "$config_file" .conf)
                local config_prefix=$(get_first_four_chars "$config_name")
                
                if [ "$env_prefix" = "$config_prefix" ]; then
                    echo "$config_file"
                    return 0
                fi
            fi
        done
    fi
    
    # Fallback: try to find any .conf file
    if [ -d "$env_path" ]; then
        for config_file in "${env_path}"/*.conf; do
            if [ -f "$config_file" ]; then
                echo "$config_file"
                return 0
            fi
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
            if [ -f "$tfvars_file" ]; then
                local tfvars_name=$(basename "$tfvars_file" .tfvars)
                local tfvars_prefix=$(get_first_four_chars "$tfvars_name")
                
                if [ "$env_prefix" = "$tfvars_prefix" ]; then
                    echo "$tfvars_file"
                    return 0
                fi
            fi
        done
    fi
    
    # Fallback: try to find any .tfvars file
    if [ -d "$config_path" ]; then
        for tfvars_file in "${config_path}"/*.tfvars; do
            if [ -f "$tfvars_file" ]; then
                echo "$tfvars_file"
                return 0
            fi
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

# Use files to store projects and workflows
PROJECTS_FILE=$(mktemp)
WORKFLOWS_FILE=$(mktemp)

echo "Starting project discovery..."

# Find all projects with env directories
find . -type d -name "env" | while read -r env_dir; do
    project_dir=$(dirname "$env_dir")
    
    if is_terraform_project "$project_dir"; then
        project_name=$(get_project_name "$project_dir")
        
        environments=$(get_environments "$project_dir")
        if [ -n "$environments" ]; then
            echo "$environments" | while IFS= read -r env; do
                if [ -n "$env" ]; then
                    env_path="$project_dir/env/${env}"
                    if [ -d "$env_path" ]; then
                        # Get config files
                        backend_config=$(find_matching_backend_config "$project_dir" "$env")
                        tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
                        
                        if [ -n "$backend_config" ] && [ -n "$tfvars_file" ]; then
                            # Store project configuration
                            {
                            echo "PROJECT_START"
                            echo "NAME:${project_name}-${env}"
                            echo "DIR:${project_dir#./}"
                            echo "WORKFLOW:${env}_workflow"
                            echo "BACKEND:${backend_config}"
                            echo "TFVARS:${tfvars_file}"
                            echo "PROJECT_END"
                            } >> "$PROJECTS_FILE"
                            
                            # Store workflow requirement
                            echo "${env}_workflow" >> "$WORKFLOWS_FILE"
                        else
                            echo "Warning: Missing config files for $project_dir env $env"
                        fi
                    fi
                fi
            done
        fi
    fi
done

# Process projects and write to atlantis.yaml
PROJECT_COUNT=0
if [ -s "$PROJECTS_FILE" ]; then
    while IFS= read -r line; do
        case $line in
            PROJECT_START*)
                unset PROJECT_NAME PROJECT_DIR WORKFLOW_NAME BACKEND_CONFIG TFVARS_FILE
                ;;
            NAME:*)
                PROJECT_NAME="${line#NAME:}"
                ;;
            DIR:*)
                PROJECT_DIR="${line#DIR:}"
                ;;
            WORKFLOW:*)
                WORKFLOW_NAME="${line#WORKFLOW:}"
                ;;
            BACKEND:*)
                BACKEND_CONFIG="${line#BACKEND:}"
                ;;
            TFVARS:*)
                TFVARS_FILE="${line#TFVARS:}"
                ;;
            PROJECT_END*)
                if [ -n "$PROJECT_NAME" ] && [ -n "$PROJECT_DIR" ] && [ -n "$WORKFLOW_NAME" ]; then
                    {
                    echo "  - name: $PROJECT_NAME"
                    echo "    dir: $PROJECT_DIR"
                    echo "    autoplan:"
                    echo "      enabled: true"
                    echo "      when_modified:"
                    echo "        - \"$PROJECT_DIR/*.tf\""
                    echo "        - \"$PROJECT_DIR/config/*.tfvars\""
                    echo "        - \"$PROJECT_DIR/env/*/*\""
                    echo "    terraform_version: v1.6.6"
                    echo "    workflow: $WORKFLOW_NAME"
                    echo "    apply_requirements:"
                    echo "      - approved"
                    echo "      - mergeable"
                    } >> atlantis.yaml
                    
                    PROJECT_COUNT=$((PROJECT_COUNT + 1))
                    echo "Added project: $PROJECT_NAME"
                fi
                ;;
        esac
    done < "$PROJECTS_FILE"
fi

# Generate workflows section
cat >> atlantis.yaml <<EOF
workflows:
EOF

# Generate workflows for all unique workflows found
if [ -s "$WORKFLOWS_FILE" ]; then
    sort -u "$WORKFLOWS_FILE" | while IFS= read -r workflow; do
        if [ -n "$workflow" ]; then
            # Extract environment name from workflow name (remove _workflow suffix)
            env="${workflow%_workflow}"
            
            {
            echo "  ${workflow}:"
            echo "    plan:"
            echo "      steps:"
            echo "        - run: |"
            echo "            echo \"Project: \$PROJECT_NAME\""
            echo "            echo \"Environment: $env\""
            echo "            cd \"\$PROJECT_DIR\""
            echo "            rm -rf .terraform .terraform.lock.hcl"
            echo "            terraform init -reconfigure -lock=false -input=false"
            echo "            terraform plan -lock-timeout=10m -out=\$PLANFILE"
            echo "    apply:"
            echo "      steps:"
            echo "        - run: |"
            echo "            echo \"Applying project: \$PROJECT_NAME\""
            echo "            cd \"\$PROJECT_DIR\""
            echo "            terraform apply -auto-approve \$PLANFILE"
            } >> atlantis.yaml
            
            echo "Added workflow: $workflow"
        fi
    done
else
    # Add a default workflow if no specific workflows were found
    cat >> atlantis.yaml <<EOF
  default_workflow:
    plan:
      steps:
        - init:
            extra_args: [ "-lock=false", "-input=false" ]
        - plan:
            extra_args: [ "-lock-timeout=10m" ]
    apply:
      steps:
        - apply:
            extra_args: [ "-auto-approve" ]
EOF
    echo "Added default workflow"
fi

# Clean up
rm -f "$PROJECTS_FILE" "$WORKFLOWS_FILE"

echo "Generated atlantis.yaml successfully"
echo "Total projects configured: $PROJECT_COUNT"

# Simple validation - check if workflows are defined
echo "Workflow validation:"
if grep -q "workflow:" atlantis.yaml; then
    echo "✓ Workflows are configured"
else
    echo "⚠ No workflows found in generated configuration"
fi