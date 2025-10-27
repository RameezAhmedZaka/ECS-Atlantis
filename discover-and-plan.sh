#!/bin/bash
set -euo pipefail

echo "=== DYNAMIC DISCOVERY AND PLAN ==="
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la

# Better way to get changed files - use git diff directly
if [[ -n "${ATLANTIS_PULL_NUM:-}" ]]; then
    # Running in Atlantis - use git to get changed files
    CHANGED_FILES=$(git diff --name-only "origin/HEAD...HEAD" 2>/dev/null || git diff --name-only HEAD~1 HEAD 2>/dev/null)
else
    # Fallback for local testing
    CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null)
fi

echo "Changed files found:"
echo "$CHANGED_FILES"

# If no changed files detected, try alternative method
if [[ -z "$CHANGED_FILES" ]]; then
    echo "No changed files detected via git diff, trying find..."
    # Fallback: plan all apps if we can't detect changes
    find application -maxdepth 2 -name "main.tf" -type f | while read -r main_tf; do
        app_dir=$(dirname "$main_tf")
        app_name=$(basename "$app_dir")
        echo "Found app: $app_name in $app_dir"
        
        # Plan both environments as fallback
        plan_app "$app_dir" "$app_name" "staging"
        plan_app "$app_name" "$app_dir" "production"
    done
    exit 0
fi

# Function to plan an app
plan_app() {
    local app_dir="$1"
    local app_name="$2"
    local environment="$3"
    
    echo ""
    echo "=== PLANNING: $app_name - $environment ==="
    
    case $environment in
        "staging")
            backend_config="env/staging/stage.conf"
            var_file="config/stage.tfvars"
            plan_file="staging.tfplan"
            ;;
        "production")
            backend_config="env/production/prod.conf"
            var_file="config/production.tfvars"
            plan_file="production.tfplan"
            ;;
        *)
            echo "Unknown environment: $environment"
            return 1
            ;;
    esac
    
    # Validate required files exist
    if [[ ! -f "$app_dir/$backend_config" ]]; then
        echo "❌ Backend config not found: $app_dir/$backend_config"
        echo "Available files in $app_dir:"
        ls -la "$app_dir/" 2>/dev/null || echo "Directory not accessible"
        return 1
    fi
    
    if [[ ! -f "$app_dir/$var_file" ]]; then
        echo "❌ Var file not found: $app_dir/$var_file"
        echo "Available config files:"
        ls -la "$app_dir/config/" 2>/dev/null || echo "Config directory not found"
        return 1
    fi
    
    echo "App directory: $app_dir"
    echo "Backend config: $backend_config"
    echo "Var file: $var_file"
    
    # Initialize and plan
    echo "Step 1: Initializing..."
    cd "$app_dir" || { echo "Failed to enter directory: $app_dir"; return 1; }
    
    terraform init -backend-config="$backend_config" -reconfigure -input=false
    if [ $? -ne 0 ]; then
        echo "❌ Init failed for $app_name - $environment"
        cd - >/dev/null
        return 1
    fi
    
    echo "Step 2: Planning..."
    terraform plan -var-file="$var_file" -out="$plan_file"
    if [ $? -ne 0 ]; then
        echo "❌ Plan failed for $app_name - $environment"
        cd - >/dev/null
        return 1
    fi
    
    cd - >/dev/null
    echo "✅ Successfully planned: $app_name - $environment"
}

# Parse changed files and plan affected apps
declare -A planned_apps

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    
    echo "Processing changed file: $file"
    
    # Extract app name from path
    if [[ "$file" =~ ^application/([^/]+)/ ]]; then
        app_name="${BASH_REMATCH[1]}"
        app_dir="application/$app_name"
        
        echo "Detected app: $app_name from file: $file"
        
        # Determine affected environments
        if [[ "$file" == *"main.tf" ]] || [[ "$file" == *"providers.tf" ]] || [[ "$file" == *"variables.tf" ]] || [[ "$file" == *"backend.tf" ]]; then
            # Core files affect both environments
            echo "  → Core Terraform file - planning both environments"
            plan_app "$app_dir" "$app_name" "staging"
            plan_app "$app_dir" "$app_name" "production"
            
        elif [[ "$file" == *"stage.tfvars" ]] || [[ "$file" == *"staging/"* ]] || [[ "$file" == *"env/staging/"* ]]; then
            # Staging-specific changes
            echo "  → Staging-specific file - planning staging only"
            plan_app "$app_dir" "$app_name" "staging"
            
        elif [[ "$file" == *"production.tfvars" ]] || [[ "$file" == *"production/"* ]] || [[ "$file" == *"env/production/"* ]]; then
            # Production-specific changes
            echo "  → Production-specific file - planning production only"
            plan_app "$app_dir" "$app_name" "production"
            
        else
            # Unknown file type - plan both to be safe
            echo "  → Other file - planning both environments to be safe"
            plan_app "$app_dir" "$app_name" "staging"
            plan_app "$app_dir" "$app_name" "production"
        fi
    else
        echo "File not in application directory: $file"
    fi
done <<< "$CHANGED_FILES"

echo ""
echo "=== PLANNING COMPLETE ==="