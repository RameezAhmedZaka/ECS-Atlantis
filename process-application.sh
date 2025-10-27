#!/bin/bash
set -euo pipefail

ENV="$1"
echo "=== STARTING $ENV at $(date) ==="

# Get changed files from Atlantis
CHANGED_FILES="${ATLANTIS_MODIFIED_FILES:-}"
echo "Changed files: $CHANGED_FILES"

# Find all applications
mapfile -t all_dirs < <(find application -maxdepth 2 -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)

# If we have specific changed files, filter to only changed apps
if [[ -n "$CHANGED_FILES" ]]; then
    echo "Filtering based on changed files..."
    changed_dirs=()
    for d in "${all_dirs[@]}"; do
        app_name=$(basename "$d")
        # Check if any files in this app were changed
        if echo "$CHANGED_FILES" | grep -q "^application/$app_name/"; then
            changed_dirs+=("$d")
            echo "  - $app_name has changes"
        fi
    done
    
    # If specific apps changed, use only those. Otherwise use all.
    if [[ ${#changed_dirs[@]} -gt 0 ]]; then
        dirs=("${changed_dirs[@]}")
        echo "Processing ${#dirs[@]} changed application(s)"
    else
        dirs=("${all_dirs[@]}")
        echo "No specific app changes detected, processing all ${#dirs[@]} applications"
    fi
else
    dirs=("${all_dirs[@]}")
    echo "Processing all ${#dirs[@]} applications"
fi

if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No applications found!"
    exit 1
fi

echo "Applications to process in $ENV:"
printf '  - %s\n' "${dirs[@]}"

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

SUCCESS_COUNT=0
FAIL_COUNT=0

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
            *)
                echo "Unknown environment: $ENV"
                continue
                ;;
        esac
        
        echo "Directory: $d"
        echo "Backend config: $BACKEND_CONFIG"
        echo "Var file: $VAR_FILE"
        
        # Check if files exist for this environment
        if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
            echo "⚠️ Backend config not found: $d/$BACKEND_CONFIG (skipping for $ENV)"
            continue
        fi
        
        if [[ ! -f "$d/$VAR_FILE" ]]; then
            echo "⚠️ Var file not found: $d/$VAR_FILE (skipping for $ENV)"
            continue
        fi
        
        # Clean up previous terraform initialization
        rm -rf "$d/.terraform"
        
        # Initialize with backend config
        echo "Step 1: Initializing..."
        if ! timeout 120 terraform -chdir="$d" init -upgrade \
            -backend-config="$BACKEND_CONFIG" \
            -reconfigure \
            -input=false; then
            echo "❌ Init failed for $d in $ENV"
            ((FAIL_COUNT++))
            continue
        fi
        
        # Create unique plan file name
        PLAN_NAME=$(echo "${d}_${ENV}" | tr "/" "_" | sed 's/application_//')
        PLAN="/tmp/${PLAN_NAME}.tfplan"
        
        echo "Step 2: Planning... Output: $PLAN"
        if timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN"; then
            echo "$d|$PLAN" >> "$PLANLIST"
            echo "✅ Successfully planned $APP_NAME for $ENV"
            ((SUCCESS_COUNT++))
        else
            echo "❌ Plan failed for $d in $ENV"
            ((FAIL_COUNT++))
            continue
        fi
    else
        echo "⚠️ Skipping $d (main.tf missing)"
    fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Summary for $ENV: $SUCCESS_COUNT successful, $FAIL_COUNT failed"

if [[ -f "$PLANLIST" ]] && [[ -s "$PLANLIST" ]]; then
    echo "Plan files created for $ENV:"
    cat "$PLANLIST"
else
    echo "No plan files created for $ENV"
fi