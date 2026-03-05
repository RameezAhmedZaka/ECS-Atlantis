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

# Check if a directory is a Terraform project (has env directory and main.tf)
is_terraform_project() {
    local dir="$1"
    # Must have env directory to be a deployable project
    if [ ! -d "$dir/env" ]; then
        return 1
    fi
    # Must have main.tf
    if [ ! -f "$dir/main.tf" ]; then
        return 1
    fi
    # Must have at least one environment subdirectory
    if [ -z "$(find "$dir/env" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then
        return 1
    fi
    return 0
}

# Function to find all Terraform projects recursively (excluding modules)
find_terraform_projects() {
    local search_path="$1"
    local projects=()
    
    # Find all directories that contain main.tf AND have an env directory
    while IFS= read -r -d '' main_tf_file; do
        project_dir=$(dirname "$main_tf_file")
        
        # Check if this is a project (has env directory)
        if [ -d "$project_dir/env" ]; then
            # Check if env directory has at least one subdirectory
            if [ -n "$(find "$project_dir/env" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then
                projects+=("$project_dir")
            fi
        fi
    done < <(find "$search_path" -type f -name "main.tf" -not -path "*/modules/*" -print0 2>/dev/null || true)
    
    # Return unique projects
    printf '%s\n' "${projects[@]}" | sort -u
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
    
    if [ ! -d "$env_path" ]; then
        echo ""
        return
    fi
    
    local env_prefix=$(get_first_four_chars "$env")
    
    # Find all .conf files in the env directory
    for config_file in "${env_path}"/*.conf; do
        [ -f "$config_file" ] || continue
        local config_name=$(basename "$config_file" .conf)
        local config_prefix=$(get_first_four_chars "$config_name")
        
        if [ "$env_prefix" = "$config_prefix" ]; then
            echo "$config_file"
            return 0
        fi
    done
    
    # Fallback: try to find any .conf file
    for config_file in "${env_path}"/*.conf; do
        [ -f "$config_file" ] && echo "$config_file" && return 0
    done
    
    echo ""
}

# Function to find matching tfvars file
find_matching_tfvars_file() {
    local project_dir="$1"
    local env="$2"
    local config_path="$project_dir/config"
    
    if [ ! -d "$config_path" ]; then
        echo ""
        return
    fi
    
    local env_prefix=$(get_first_four_chars "$env")
    
    # Find all .tfvars files in the config directory
    for tfvars_file in "${config_path}"/*.tfvars; do
        [ -f "$tfvars_file" ] || continue
        local tfvars_name=$(basename "$tfvars_file" .tfvars)
        local tfvars_prefix=$(get_first_four_chars "$tfvars_name")
        
        if [ "$env_prefix" = "$tfvars_prefix" ]; then
            echo "$tfvars_file"
            return 0
        fi
    done
    
    # Fallback: try to find any .tfvars file
    for tfvars_file in "${config_path}"/*.tfvars; do
        [ -f "$tfvars_file" ] && echo "$tfvars_file" && return 0
    done
    
    echo ""
}

# Function to get role ARN based on environment
get_role_arn() {
    local env="$1"
    
    case "$env" in
        production|prod)
            # Production role
            echo "arn:aws:iam::569023477847:role/atlantis-cross-account-role-prod"
            ;;
        staging|stage|stg)
            # Staging role
            echo "arn:aws:iam::569023477847:role/atlantis-cross-account-role-stage"
            ;;
        *)
            # Default role - empty for other environments
            echo ""
            ;;
    esac
}

# Function to update provider.tf with role ARN
update_provider_tf() {
    local project_dir="$1"
    local env="$2"
    local role_arn="$3"
    
    local provider_file="$project_dir/provider.tf"
    
    # Create or update provider.tf with correct configuration
    echo "    Configuring provider.tf with role: $role_arn"
    
    # Create a backup if file exists
    if [ -f "$provider_file" ]; then
        cp "$provider_file" "${provider_file}.backup"
    fi
    
    # Write the correct provider configuration
    cat > "$provider_file" <<EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  assume_role {
    role_arn = "$role_arn"
  }
}

# Variables needed for the provider
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
EOF
    
    echo "    Updated $provider_file with role: $role_arn"
    return 0
}

# Function to restore provider.tf from backup
restore_provider_tf() {
    local project_dir="$1"
    local provider_file="$project_dir/provider.tf"
    local backup_file="${provider_file}.backup"
    
    if [ -f "$backup_file" ]; then
        mv "$backup_file" "$provider_file"
        echo "    Restored $provider_file from backup"
    fi
}

# Function to get project name based on directory path
get_project_name() {
    local project_dir="$1"
    # Remove leading ./ if present
    project_dir="${project_dir#./}"
    # Remove the base folder prefix (applications/ or SPA/) if present
    project_dir="${project_dir#applications/}"
    project_dir="${project_dir#SPA/}"
    # Replace remaining slashes with dashes
    echo "$project_dir" | tr '/' '-'
}

# Function to calculate relative path from env dir to project root
get_relative_path_to_root() {
    local env_dir="$1"
    local project_dir="$2"
    
    # Count how many levels deep the env dir is from project dir
    local rel_path="${env_dir#$project_dir/}"
    local levels_deep=$(echo "$rel_path" | tr -cd '/' | wc -c)
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
ALL_PROJECTS_FILE=$(mktemp)

echo "Searching for Terraform projects in applications and SPA folders..."

# Check if at least one of the directories exists
if [ ! -d "applications" ] && [ ! -d "SPA" ]; then
    echo "Error: Neither 'applications' nor 'SPA' directory found in current path"
    exit 1
fi

# Find all Terraform projects from both folders
> "$ALL_PROJECTS_FILE"  # Clear the file

if [ -d "applications" ]; then
    echo "Searching in applications folder..."
    find_terraform_projects "applications" >> "$ALL_PROJECTS_FILE"
fi

if [ -d "SPA" ]; then
    echo "Searching in SPA folder..."
    find_terraform_projects "SPA" >> "$ALL_PROJECTS_FILE"
fi

# Sort and deduplicate projects (just in case)
sort -u -o "$ALL_PROJECTS_FILE" "$ALL_PROJECTS_FILE"

# Count projects found
project_count=$(wc -l < "$ALL_PROJECTS_FILE")
echo "Found $project_count Terraform projects total"

# First pass: discover environments and configs
while IFS= read -r project_dir; do
    [ -z "$project_dir" ] && continue
    echo "Processing project: $project_dir"
    
    # Double-check it's a valid project
    if ! is_terraform_project "$project_dir"; then
        echo "  Skipping - not a valid Terraform project"
        continue
    fi
    
    # Get environments
    environments=$(get_environments "$project_dir")
    
    echo "  Found environments: $(echo $environments | tr '\n' ' ')"
    
    echo "$environments" | while IFS= read -r env; do
        [ -n "$env" ] || continue
        
        # Discover config files for this environment
        backend_config=$(find_matching_backend_config "$project_dir" "$env")
        tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
        
        # Get role ARN for this environment
        role_arn=$(get_role_arn "$env")
        
        # Store configs if found
        if [ -n "$backend_config" ]; then
            # Use a compound key with project and env, including role ARN
            echo "${project_dir}|${env}|${backend_config}|${role_arn}" >> "$BACKEND_FILE"
            echo "    Found backend config for $env: $backend_config"
            if [ -n "$role_arn" ]; then
                echo "      Will configure role: $role_arn in provider.tf"
            fi
        else
            echo "    Warning: No backend config found for $env"
        fi
        
        if [ -n "$tfvars_file" ]; then
            echo "${project_dir}|${env}|${tfvars_file}|${role_arn}" >> "$TFVARS_FILE"
            echo "    Found tfvars file for $env: $tfvars_file"
        else
            echo "    Warning: No tfvars file found for $env"
        fi
    done
done < "$ALL_PROJECTS_FILE"

# Function to get config from stored files
get_backend_config_for_project() {
    local project_dir="$1"
    local env="$2"
    # Use awk with pipe delimiter to properly handle paths with colons
    awk -F'|' -v proj="$project_dir" -v env_name="$env" '$1 == proj && $2 == env_name {print $3}' "$BACKEND_FILE" | head -1
}

get_tfvars_file_for_project() {
    local project_dir="$1"
    local env="$2"
    # Use awk with pipe delimiter to properly handle paths with colons
    awk -F'|' -v proj="$project_dir" -v env_name="$env" '$1 == proj && $2 == env_name {print $3}' "$TFVARS_FILE" | head -1
}

get_role_for_project() {
    local project_dir="$1"
    local env="$2"
    # Get role ARN from backend file
    awk -F'|' -v proj="$project_dir" -v env_name="$env" '$1 == proj && $2 == env_name {print $4}' "$BACKEND_FILE" | head -1
}

# Debug: Show what configs were found
echo "Debug: Backend configs found:"
cat "$BACKEND_FILE" || echo "  None"
echo "Debug: TFVars files found:"
cat "$TFVARS_FILE" || echo "  None"

# Second pass: generate projects for all discovered Terraform projects
echo "Generating project configurations..."

# Create a file to store unique workflow names
WORKFLOWS_FILE=$(mktemp)

while IFS= read -r project_dir; do
    [ -z "$project_dir" ] && continue
    
    # Skip if not a valid project
    if ! is_terraform_project "$project_dir"; then
        continue
    fi
    
    project_name=$(get_project_name "$project_dir")
    
    # Get environments
    environments=$(get_environments "$project_dir")
    
    echo "$environments" | while IFS= read -r env; do
        [ -z "$env" ] && continue
        env_path="$project_dir/env/${env}"
        [ ! -d "$env_path" ] && continue

        # Get config files specific to this project
        backend_config=$(get_backend_config_for_project "$project_dir" "$env")
        tfvars_file=$(get_tfvars_file_for_project "$project_dir" "$env")
        role_arn=$(get_role_for_project "$project_dir" "$env")
        
        if [ -z "$backend_config" ]; then
            backend_config=$(find_matching_backend_config "$project_dir" "$env")
        fi
        
        if [ -z "$tfvars_file" ]; then
            tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
        fi
        
        if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
            echo "Warning: Missing config files for $project_dir env $env"
            echo "  Backend config: ${backend_config:-"not found"}"
            echo "  TFVars file: ${tfvars_file:-"not found"}"
            continue
        fi

        # Update provider.tf with role ARN if needed
        if [ -n "$role_arn" ]; then
            echo "  Updating provider for $env in $project_dir"
            if update_provider_tf "$project_dir" "$env" "$role_arn"; then
                echo "  Successfully updated provider for $env environment in $project_dir"
            fi
        fi

        # Calculate relative path from env directory to project root
        relative_to_root=$(get_relative_path_to_root "$env_path" "$project_dir")
        
        # Create a unique workflow name for this project-environment combination
        workflow_name="${project_name}-${env}-workflow"
        echo "$workflow_name" >> "$WORKFLOWS_FILE"
        
        # Store project info for reference
        echo "${project_dir}|${env}|${relative_to_root}|${workflow_name}|${role_arn}" >> "$PROJECT_INFO_FILE"
        
        # Write project configuration
        {
        echo "  - name: ${project_name}-${env}"
        echo "    dir: $env_path"
        echo "    autoplan:"
        echo "      enabled: false"
        echo "      when_modified:"
        echo "        - \"${relative_to_root}/*.tf\""
        echo "        - \"${relative_to_root}/*.tfvars\""
        echo "        - \"${relative_to_root}/config/*.tfvars\""
        echo "        - \"${relative_to_root}/env/*/*\""
        echo "    terraform_version: v1.6.6"
        echo "    workflow: ${workflow_name}"
        echo "    apply_requirements:"
        echo "      - approved"
        echo "      - mergeable"
        } >> atlantis.yaml
    done
done < "$ALL_PROJECTS_FILE"

# Generate workflows for each unique project-environment combination
if [ -s "$PROJECT_INFO_FILE" ]; then
    cat >> atlantis.yaml <<EOF
workflows:
EOF

    # Read each project info and create its workflow
    while IFS='|' read -r project_dir env relative_to_root workflow_name role_arn; do
        [ -z "$project_dir" ] && continue
        
        echo "Generating workflow: $workflow_name for $project_dir env $env"
        
        # Get config files for this specific project and environment
        backend_config=$(get_backend_config_for_project "$project_dir" "$env")
        tfvars_file=$(get_tfvars_file_for_project "$project_dir" "$env")

        if [ -z "$backend_config" ] || [ -z "$tfvars_file" ]; then
            echo "Warning: Missing config files for $project_dir env $env, skipping workflow $workflow_name"
            continue
        fi

        backend_config_file=$(basename "$backend_config")
        tfvars_config_file=$(basename "$tfvars_file")

        if [ -z "$relative_to_root" ]; then
            relative_to_root="../.."  # Default fallback
        fi

        # Write workflow configuration - With debugging
        {
        echo "  ${workflow_name}:"
        echo "    plan:"
        echo "      steps:"
        echo "        - run: |"
        echo "            echo \"Using provider-configured AWS role for $env environment\""
        echo "            echo \"Current directory: \$(pwd)\""
        echo "            echo \"Project directory: \$PROJECT_DIR\""
        echo "            echo \"Changing to: \$(dirname \"\$PROJECT_DIR\")/$relative_to_root\""
        echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/$relative_to_root\""
        echo "            echo \"Now in: \$(pwd)\""
        echo "            echo \"Checking provider configuration:\""
        echo "            if [ -f provider.tf ]; then"
        echo "              echo \"provider.tf exists:\""
        echo "              cat provider.tf"
        echo "            else"
        echo "              echo \"No provider.tf file found!\""
        echo "            fi"
        echo "            echo \"Current AWS identity before assume_role:\""
        echo "            aws sts get-caller-identity || echo \"Failed to get identity\""
        echo "            rm -rf .terraform .terraform.lock.hcl"
        echo "            terraform init -backend-config=\"env/$env/$backend_config_file\" -reconfigure -lock=false -input=false"
        echo "            echo \"AWS identity after terraform init (should be assumed role):\""
        echo "            aws sts get-caller-identity || echo \"Failed to get identity\""
        echo "            terraform plan -compact-warnings -var-file=\"config/$tfvars_config_file\" -lock-timeout=10m -out=\$PLANFILE"
        echo "    apply:"
        echo "      steps:"
        echo "        - run: |"
        echo "            echo \"Project: \$PROJECT_NAME\""
        echo "            echo \"Environment: $env\""
        echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/$relative_to_root\""
        echo "            terraform apply -auto-approve \$PLANFILE"
        } >> atlantis.yaml
    done < "$PROJECT_INFO_FILE"
    
else
    echo "Warning: No project info found, skipping workflows"
    # Still add empty workflows section
    cat >> atlantis.yaml <<EOF
workflows:
EOF
fi

# Count workflows created
workflow_count=$(sort -u "$WORKFLOWS_FILE" | wc -l)
echo "Generated $workflow_count unique workflows"

# Clean up
rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE" "$PROJECT_INFO_FILE" "$ALL_PROJECTS_FILE" "$WORKFLOWS_FILE"

echo "Generated atlantis.yaml successfully with $project_count projects and $workflow_count workflows"