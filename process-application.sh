#!/bin/bash
set -euo pipefail
ENV="$1"
echo "=== STARTING $ENV at $(date) ==="

# Find all applications (remove head limit for all apps)
mapfile -t dirs < <(find application -maxdepth 2 -name "main.tf" -type f | sed 's|/main.tf||' | sort -u)

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No applications found!"
  exit 1
fi

echo "Found ${#dirs[@]} applications"

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
        # Use separate state for production
        BACKEND_CONFIG_ABS="$d/$BACKEND_CONFIG"
        ;;
      "staging")
        BACKEND_CONFIG="env/staging/stage.conf" 
        VAR_FILE="config/staging.tfvars"
        # Use separate state for staging
        BACKEND_CONFIG_ABS="$d/$BACKEND_CONFIG"
        ;;
    esac
    
    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG_ABS"
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
    
    # Initialize with backend config (NO WORKSPACES)
    echo "Step 1: Initializing..."
    timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -input=false -reconfigure || {
      echo "Init failed for $d"
      continue
    }
    
    # PLAN file with environment in name
    PLAN="${ENV}-${APP_NAME}.tfplan"
    echo "Step 2: Planning... Output: $PLAN"
    
    # Plan with var-file (NO WORKSPACE SELECTION)
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
      echo "Plan failed for $d"
      continue
    }
    
    echo "$d|$PLAN" >> "$PLANLIST"
    echo "Successfully planned $APP_NAME for $ENV"
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"