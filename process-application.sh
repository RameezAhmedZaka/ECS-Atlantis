#!/bin/bash
set -euo pipefail

ENV="$1"
ATLANTIS_PROJECT_DIR="${2:-}"  # Get the specific project directory from Atlantis

echo "=== STARTING $ENV at $(date) ==="
echo "Project directory: $ATLANTIS_PROJECT_DIR"

# If a specific directory is provided, use only that
if [[ -n "$ATLANTIS_PROJECT_DIR" && -f "$ATLANTIS_PROJECT_DIR/main.tf" ]]; then
    dirs=("$ATLANTIS_PROJECT_DIR")
else
    # Find all applications but limit for testing
    mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
fi

if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No application found!"
    exit 1
fi

echo "Found ${#dirs[@]} application: ${dirs[*]}"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
        APP_NAME=$(basename "$d")
        echo "=== Planning $APP_NAME ($ENV) ==="
        
        case "$ENV" in
            "production")
                BACKEND_CONFIG="env/production/prod.conf"
                VAR_FILE="config/production.tfvars"
                ;;
            "staging")
                BACKEND_CONFIG="env/staging/stage.conf"   
                VAR_FILE="config/stage.tfvars"            
                ;;
            "helia")
                BACKEND_CONFIG="env/helia/helia.conf"
                VAR_FILE="config/helia.tfvars"         
                ;;
        esac
        
        echo "Directory: $d"
        echo "Backend config: $BACKEND_CONFIG"
        echo "Var file: $VAR_FILE"
        
        # Check if files exist
        if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
            echo "Backend config not found: $d/$BACKEND_CONFIG"
            continue
        fi
        
        if [[ ! -f "$d/$VAR_FILE" ]]; then
            echo "Var file not found: $d/$VAR_FILE"
            continue
        fi
        
        rm -rf "$d/.terraform"
        
        # Initialize with backend config
        echo "Step 1: Initializing..."
        timeout 120 terraform -chdir="$d" init -upgrade \
            -backend-config="$BACKEND_CONFIG" \
            -reconfigure \
            -input=false || {
            echo "Init failed for $d"
            continue
        }
        
        # Create unique plan file name
        PLAN_NAME=$(echo "${d}_${ENV}" | tr "/" "_")
        PLAN="/tmp/${PLAN_NAME}.tfplan"
        
        echo "Step 2: Planning... Output: $PLAN"
        timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
            echo "Plan failed for $d"
            continue
        }
        
        echo "$d|$PLAN" >> "$PLANLIST"
        echo "Successfully planned $APP_NAME"
    else
        echo "Skipping $d (main.tf missing)"
    fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"