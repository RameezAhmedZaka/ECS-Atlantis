#!/bin/bash

# generate-atlantis-projects.sh
# Pre-workflow hook to dynamically generate projects for Atlantis based on app structure

set -euo pipefail

echo "🚀 Starting dynamic Atlantis configuration generation..."

# Configuration
APPS_DIR="application"
TEMP_FILE="dynamic-projects.yaml"
BACKUP_FILE="atlantis.yaml.backup"

# Backup original atlantis.yaml
if [[ -f "atlantis.yaml" ]]; then
    cp "atlantis.yaml" "$BACKUP_FILE"
fi

# Function to discover environments from config and env directories
discover_environments() {
    local app_dir="$1"
    local environments=()
    
    # Check config directory for tfvars files
    if [[ -d "$app_dir/config" ]]; then
        for tfvars_file in "$app_dir/config"/*.tfvars; do
            [[ -f "$tfvars_file" ]] || continue
            env_name=$(basename "$tfvars_file" .tfvars)
            environments+=("$env_name")
        done
    fi
    
    # Check env directory for environment folders
    if [[ -d "$app_dir/env" ]]; then
        for env_dir in "$app_dir/env"/*/; do
            [[ -d "$env_dir" ]] || continue
            env_name=$(basename "$env_dir")
            environments+=("$env_name")
        done
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${environments[@]}" | sort -u
}

# Function to generate projects YAML
generate_projects_yaml() {
    cat > "$TEMP_FILE" << EOF
projects:
EOF

    local project_count=0
    
    # Find all app directories
    while IFS= read -r -d '' app_dir; do
        app_name=$(basename "$app_dir")
        echo "🔍 Processing application: $app_name"
        
        # Discover environments for this app
        environments=$(discover_environments "$app_dir")
        
        if [[ -z "$environments" ]]; then
            echo "   ⚠️  No environments found, creating default project"
            cat >> "$TEMP_FILE" << PROJECTEOF
  - name: ${app_name}-default
    dir: ${app_dir}
    workspace: default
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - "**/*.tf"
        - "**/*.tfvars"
    terraform_version: v1.5.0
    apply_requirements:
      - approved

PROJECTEOF
            ((project_count++))
        else
            # Create project for each environment
            while IFS= read -r env_name; do
                [[ -z "$env_name" ]] && continue
                
                echo "   ✅ Creating project for environment: $env_name"
                
                cat >> "$TEMP_FILE" << PROJECTEOF
  - name: ${app_name}-${env_name}
    dir: ${app_dir}
    workspace: ${env_name}
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - "**/*.tf"
        - "**/*.tfvars"
        - "**/.conf"
    terraform_version: v1.5.0
    apply_requirements:
      - approved

PROJECTEOF
                ((project_count++))
            done <<< "$environments"
        fi
    done < <(find "$APPS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
    
    echo "$project_count"
}

# Main execution
echo "📁 Scanning applications directory: $APPS_DIR"

if [[ ! -d "$APPS_DIR" ]]; then
    echo "❌ Applications directory '$APPS_DIR' not found!"
    exit 1
fi

# Generate projects YAML
project_count=$(generate_projects_yaml)

if [[ "$project_count" -eq 0 ]]; then
    echo "⚠️  No projects found. Creating fallback configuration."
    cat > "$TEMP_FILE" << EOF
projects:
  - name: default
    dir: .
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "*.tfvars"
    terraform_version: v1.5.0
EOF
    project_count=1
fi

# Create final atlantis.yaml
cat > "atlantis.yaml" << EOF
version: 3
automerge: false
parallel_plan: true
parallel_apply: true

$(cat "$TEMP_FILE")

workflows:
  default:
    plan:
      steps:
        - init
        - plan:
            extra_args: ["-lock=false"]
    apply:
      steps:
        - apply

allowed_regexp_prefixes:
  - ".*"
EOF

# Cleanup
rm -f "$TEMP_FILE"

echo "✅ Successfully generated atlantis.yaml with $project_count projects!"
echo "📋 Summary of generated projects:"

# Display project summary
grep "name:" "atlantis.yaml" | grep -v "atlantis.yaml" | sed 's/^[[:space:]]*//' | while read -r line; do
    echo "   📍 $line"
done

echo "🎉 Dynamic Atlantis configuration complete!"