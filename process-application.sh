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
SUCCESSFUL_PLANS=0
HAS_ERRORS=false

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")
    
    # HARDCONFIG CONFIG PATHS
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
    
    if ! timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -backend-config="key=$key" \
      -reconfigure -input=false; then
      echo "Init failed for $d"
      HAS_ERRORS=true
      continue
    fi
    
    echo "State key: $key"
    
    # Workspace with timeout
    echo "Step 2: Setting workspace..."
    if ! timeout 30 terraform -chdir="$d" workspace select default 2>/dev/null && \
       ! timeout 30 terraform -chdir="$d" workspace new default 2>/dev/null; then
      echo "Workspace setup failed for $d"
      HAS_ERRORS=true
      continue
    fi
    
    PLAN="${ENV}.tfplan"
    echo "Step 3: Planning... Output: $PLAN"
    
    # Plan with var-file
    if timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN"; then
      echo "$d|$PLAN" >> "$PLANLIST"
      ((SUCCESSFUL_PLANS++))
      echo "✅ Successfully planned $APP_NAME for $ENV"
    else
      echo "Plan failed for $d"
      HAS_ERRORS=true
      continue
    fi
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Successfully planned $SUCCESSFUL_PLANS application for $ENV environment"

if [[ $SUCCESSFUL_PLANS -eq 0 ]]; then
  echo "❌ No application were successfully planned"
  exit 1
else
  echo "Plan files created:"
  cat "$PLANLIST" 2>/dev/null || echo "No plan files created"
  echo "✅ Workflow completed successfully with $SUCCESSFUL_PLANS successful plans"
  exit 0
fi