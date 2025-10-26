#!/bin/bash
set -euo pipefail
ENV="$1"
echo "=== STARTING $ENV at $(date) ==="

# Find application that ACTUALLY have this environment configuration
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application found!"
  exit 1
fi

echo "Found ${#dirs[@]} total application: ${dirs[*]}"

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
VALID_APPS=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")
    
    # DYNAMIC CONFIG PATHS - Check if environment config exists for this app
    case "$ENV" in
      "production")
        BACKEND_CONFIG="env/production/prod.conf"
        VAR_FILE="config/production.tfvars"
        key="application/${APP_NAME}/${ENV}/terraform1.tfstate"
        ;;
      "staging")
        BACKEND_CONFIG="env/staging/stage.conf"
        VAR_FILE="config/stage.tfvars"
        key="application/${APP_NAME}/${ENV}/terraform1.tfstate"
        ;;
      "helia")
        BACKEND_CONFIG="env/helia/helia.conf"
        VAR_FILE="config/helia.tfvars"
        key="application/${APP_NAME}/${ENV}/terraform1.tfstate"
        ;;
      *)
        echo "Unknown environment: $ENV"
        exit 1
        ;;
    esac
    
    # Check if this app has configuration for the requested environment
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "SKIPPING $APP_NAME: Backend config not found: $d/$BACKEND_CONFIG"
      continue
    fi
    
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "SKIPPING $APP_NAME: Var file not found: $d/$VAR_FILE"
      continue
    fi
    
    # Only process apps that have the environment configuration
    echo "=== Planning $APP_NAME ($ENV) ==="
    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG"
    echo "Var file: $VAR_FILE"
    
    rm -rf "$d/.terraform"
    
    # Initialize with backend config
    echo "Step 1: Initializing..."
    
    timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -backend-config="key=$key" \
      -reconfigure \
      -input=false || {
      echo "Init failed for $d"
      continue
    }
    
    echo "State key: $key"
    
    # Workspace with timeout
    echo "Step 2: Setting workspace..."
    timeout 30 terraform -chdir="$d" workspace select default 2>/dev/null || \
    timeout 30 terraform -chdir="$d" workspace new default || {
      echo "Workspace setup failed for $d"
      continue
    }
    
    PLAN="${ENV}.tfplan"
    echo "Step 3: Planning... Output: $PLAN"
    
    # Plan with var-file
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
      echo "Plan failed for $d"
      continue
    }
    
    echo "$d|$PLAN" >> "$PLANLIST"
    ((VALID_APPS++))
    echo "Successfully planned $APP_NAME for $ENV"
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Successfully processed $VALID_APPS application for $ENV environment"
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"