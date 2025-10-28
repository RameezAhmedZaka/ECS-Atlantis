#!/bin/bash
set -euo pipefail
ENV="$1"
RAW_FILTER="${2:-}"

echo "=== STARTING $ENV at $(date) ==="

# Parse arguments (your existing code)
DESTROY_FLAG=false
APP_FILTER=""
IFS=',' read -ra ARGS <<< "$RAW_FILTER"
for arg in "${ARGS[@]}"; do
    arg_clean=$(echo "$arg" | xargs)
    case "$arg_clean" in
        -destroy|--destroy)
            echo "❌ You cannot perform this action. Destroy is disabled and cannot be run."
            exit 1
            ;;
        --)
            ;;
        *)
            if [[ -n "$arg_clean" ]]; then
                APP_FILTER="$arg_clean"
            fi
            ;;
    esac
done

echo "App filter: $APP_FILTER"

# Find application directories
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application found!"
  exit 1
fi

echo "Found ${#dirs[@]} application: ${dirs[*]}"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
CHANGED_APPS_LIST="/tmp/atlantis_changed_apps_${ENV}.lst"  # New file for changed apps only
: > "$PLANLIST"
: > "$CHANGED_APPS_LIST"  # Initialize changed apps list

processed_count=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")

    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ==="
      continue
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
    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    echo "Step 3: Planning... Output: $PLAN"
    
    # Add destroy flag if needed
    DESTROY_ARG=""
    if [[ "$DESTROY_FLAG" == "true" ]]; then
      DESTROY_ARG="-destroy"
      echo "DESTROY MODE ENABLED"
    fi
    
    # Create a temporary file to capture plan output
    PLAN_OUTPUT="/tmp/plan_output_${APP_NAME}_${ENV}.txt"
    
    # Plan and capture output
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" $DESTROY_ARG -out="$PLAN" 2>&1 | tee "$PLAN_OUTPUT" || {
      echo "Plan failed for $d"
      continue
    }

    # Check if plan has changes (not "No changes")
    if grep -q "No changes." "$PLAN_OUTPUT"; then
      echo "✅ No changes for $APP_NAME - skipping from changed applications list"
      rm -f "$PLAN"  # Remove the plan file since no changes
    else
      echo "🔄 Changes detected for $APP_NAME - adding to changed applications"
      echo "$d|$PLAN" >> "$PLANLIST"
      echo "$APP_NAME" >> "$CHANGED_APPS_LIST"  # Add to changed apps list
      # ((processed_count++))
    fi
    
    # Clean up
    rm -f "$PLAN_OUTPUT"
    
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

if [[ -n "$APP_FILTER" && $processed_count -eq 0 ]]; then
  echo "⚠️  No applications matched filter: $APP_FILTER"
  echo "Available applications:"
  for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
      echo "  - $(basename "$d")"
    fi
  done
fi

echo "=== COMPLETED $ENV at $(date) ==="
echo "Changed applications:"
cat "$CHANGED_APPS_LIST" 2>/dev/null || echo "No applications with changes"
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"