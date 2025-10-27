#!/bin/bash
set -euo pipefail
ENV="$1"
APP_FILTER="${2:-}"  # Optional app filter

echo "=== STARTING $ENV at $(date) ==="
if [[ -n "$APP_FILTER" ]]; then
  echo "Filtering for app: $APP_FILTER"
fi

echo "=== STARTING $ENV at $(date) ==="
# Find application but limit to 2 for testing
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
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

    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ==="
      continue
    fi
        
    echo "=== Planning $APP_NAME ($ENV) ==="
    case "$ENV" in
      "production")
        BACKEND_CONFIG="env/production/prod.conf"  # Relative to app directory
        VAR_FILE="config/production.tfvars"
        ;;
      "staging")
        BACKEND_CONFIG="env/staging/stage.conf"   
        VAR_FILE="config/stage.tfvars"            
        ;;
      "helia")
        BACKEND_CONFIG="env/helia/helia.conf"
        VAR_FILE="config/helia.tfvars"             # Relative to app directory         
    esac
    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG"
    echo "Var file: $VAR_FILE"
    # Check if files exist
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "Backend config not found: $d/$BACKEND_CONFIG"
      # List available backend configs for this environment
      echo "Available backend configs for $ENV:"
      find "$d/env" -name "*.conf" 2>/dev/null | grep "$ENV" || echo "No backend configs found for $ENV"
      continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE"
      ls -la "$d/config/" 2>/dev/null || echo "config directory not found"
      continue
    fi
    rm -rf "$d/.terraform"
    # Initialize with backend config (ALWAYS use -chdir for consistency)
    echo "Step 1: Initializing..."
    echo "Using backend config: $BACKEND_CONFIG"
    timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -reconfigure \
      -input=false || {
    echo "Init failed for $d"
    continue
    }

    # FIX: Create unique plan file name with app name and environment
    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    echo "Step 3: Planning... Output: $PLAN"
    # Plan with var-file
    echo "Using var-file: $VAR_FILE"
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











