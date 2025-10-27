#!/bin/bash
set -euo pipefail

ENV="$1"
RAW_APP_FILTER="${2:-}"  # Optional app filter from Atlantis COMMENT_ARGS

echo "=== STARTING $ENV at $(date) ==="

# If there is a raw filter, clean it up
FILTER_APPS=()
if [[ -n "$RAW_APP_FILTER" ]]; then
    echo "DEBUG: Raw COMMENT_ARGS='$RAW_APP_FILTER'"
    # Split by commas
    IFS=',' read -r -a RAW_ARGS <<< "$RAW_APP_FILTER"
    for arg in "${RAW_ARGS[@]}"; do
        # Remove leading/trailing spaces and dashes
        CLEAN=$(echo "$arg" | sed 's/^-*//; s/ *$//')
        # Only include non-empty strings that are not destroy flags
        if [[ -n "$CLEAN" && "$CLEAN" != "destroy" && "$CLEAN" != "--" ]]; then
            FILTER_APPS+=("$CLEAN")
        fi
    done
    echo "Filtered apps to process: ${FILTER_APPS[*]}"
fi

# Find all applications
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No application found!"
    exit 1
fi
echo "Found ${#dirs[@]} applications: ${dirs[*]}"

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

processed_count=0
for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
        APP_NAME=$(basename "$d")

        # Skip if app filter exists and app is not in the filter
        if [[ ${#FILTER_APPS[@]} -gt 0 ]]; then
            match=false
            for f in "${FILTER_APPS[@]}"; do
                if [[ "$APP_NAME" == "$f" ]]; then
                    match=true
                    break
                fi
            done
            if [[ "$match" = false ]]; then
                echo "=== Skipping $APP_NAME (does not match filter) ==="
                continue
            fi
        fi

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

        # Check if backend config exists
        if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
            echo "Backend config not found: $d/$BACKEND_CONFIG"
            continue
        fi

        # Check if var file exists
        if [[ ! -f "$d/$VAR_FILE" ]]; then
            echo "Var file not found: $d/$VAR_FILE"
            continue
        fi

        # Clean old terraform state
        rm -rf "$d/.terraform"

        echo "Step 1: Initializing Terraform..."
        timeout 120 terraform -chdir="$d" init -upgrade \
            -backend-config="$BACKEND_CONFIG" \
            -reconfigure \
            -input=false || { echo "Init failed for $d"; continue; }

        # Step 2: Create plan
        PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
        PLAN="/tmp/${PLAN_NAME}"
        echo "Step 2: Planning... Output: $PLAN"
        timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
            echo "Plan failed for $d"
            continue
        }

        echo "$d|$PLAN" >> "$PLANLIST"
        echo "✅ Successfully planned $APP_NAME"
        ((processed_count++))
    else
        echo "Skipping $d (main.tf missing)"
    fi
done

if [[ ${#FILTER_APPS[@]} -gt 0 && $processed_count -eq 0 ]]; then
    echo "⚠️  No applications matched filter: ${FILTER_APPS[*]}"
    echo "Available applications:"
    for d in "${dirs[@]}"; do
        if [[ -f "$d/main.tf" ]]; then
            echo "  - $(basename "$d")"
        fi
    done
fi

echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"
