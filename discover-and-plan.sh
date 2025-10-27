#!/bin/bash
set -euo pipefail

echo "=== DYNAMIC DISCOVERY AND PLAN ==="

# Get changed files from Atlantis environment variables
CHANGED_FILES="${ATLANTIS_MODIFIED_FILES:-}"
BASE_REPO_DIR="${ATLANTIS_BASE_REPO_DIR:-.}"
HEAD_REPO_DIR="${ATLANTIS_HEAD_REPO_DIR:-.}"

echo "Changed files: $CHANGED_FILES"
echo "Base dir: $BASE_REPO_DIR"
echo "Head dir: $HEAD_REPO_DIR"

# Parse changed files to find affected apps and environments
declare -A apps_to_plan

IFS=',' read -ra FILES <<< "$CHANGED_FILES"
for file in "${FILES[@]}"; do
    echo "Processing changed file: $file"
    
    # Extract app name and environment from file path
    if [[ $file =~ application/([^/]+)/ ]]; then
        app_name="${BASH_REMATCH[1]}"
        app_dir="application/$app_name"
        
        # Determine which environments are affected
        if [[ $file == *"main.tf" ]] || [[ $file == *"providers.tf" ]] || [[ $file == *"variables.tf" ]] || [[ $file == *"backend.tf" ]]; then
            # Core files affect both environments
            apps_to_plan["${app_name}-staging"]="$app_dir"
            apps_to_plan["${app_name}-production"]="$app_dir"
            echo "  → Core file change: planning both staging and production for $app_name"
            
        elif [[ $file == *"stage.tfvars" ]] || [[ $file == *"staging/"* ]] || [[ $file == *"env/staging/"* ]]; then
            # Staging-specific changes
            apps_to_plan["${app_name}-staging"]="$app_dir"
            echo "  → Staging change: planning staging for $app_name"
            
        elif [[ $file == *"production.tfvars" ]] || [[ $file == *"production/"* ]] || [[ $file == *"env/production/"* ]]; then
            # Production-specific changes
            apps_to_plan["${app_name}-production"]="$app_dir"
            echo "  → Production change: planning production for $app_name"
        fi
    fi
done

# Execute plans for affected apps
for project_key in "${!apps_to_plan[@]}"; do
    app_dir="${apps_to_plan[$project_key]}"
    environment="${project_key##*-}"  # Extract staging or production
    
    echo ""
    echo "=== PLANNING: $project_key ==="
    
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
            continue
            ;;
    esac
    
    # Validate required files exist
    if [[ ! -f "$app_dir/$backend_config" ]]; then
        echo "❌ Backend config not found: $app_dir/$backend_config"
        continue
    fi
    
    if [[ ! -f "$app_dir/$var_file" ]]; then
        echo "❌ Var file not found: $app_dir/$var_file"
        continue
    fi
    
    # Initialize and plan
    echo "Initializing with: $backend_config"
    terraform -chdir="$app_dir" init -backend-config="$backend_config" -reconfigure -input=false
    
    echo "Planning with: $var_file"
    terraform -chdir="$app_dir" plan -var-file="$var_file" -out="$plan_file"
    
    echo "✅ Planned: $project_key"
done

echo ""
echo "=== PLANNING COMPLETE ==="