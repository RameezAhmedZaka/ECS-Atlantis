#!/bin/bash
set -euo pipefail
ENV="$1"
echo "=== STARTING $ENV at $(date) ==="

# Find ALL application directories and filter by environment pattern
mapfile -t dirs < <(find application -maxdepth 2 -name "main.tf" -type f | sed 's|/main.tf||' | sort -u)

# Filter directories that match the environment pattern
ENV_DIRS=()
for dir in "${dirs[@]}"; do
  if [[ "$dir" == *"-${ENV}" ]]; then
    ENV_DIRS+=("$dir")
  fi
done

# Limit to 2 for testing
ENV_DIRS=("${ENV_DIRS[@]:0:2}")

if [[ ${#ENV_DIRS[@]} -eq 0 ]]; then
  echo "No application found for environment $ENV!"
  echo "Available directories:"
  find application -type d -name "main.tf" -exec dirname {} \; 2>/dev/null | sort -u || echo "No directories found"
  exit 1
fi

echo "Found ${#ENV_DIRS[@]} application(s) for $ENV: ${ENV_DIRS[*]}"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for d in "${ENV_DIRS[@]}"; do
  # Rest of the script remains the same...
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
    esac
    
    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG"
    echo "Var file: $VAR_FILE"
    
    # Check if files exist
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "Backend config not found: $d/$BACKEND_CONFIG"
      ls -la "$d/env/" 2>/dev/null || echo "env directory not found"
      continue
    fi
    
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE"
      ls -la "$d/config/" 2>/dev/null || echo "config directory not found"
      continue
    fi
    
    # Initialize with backend config
    echo "Step 1: Initializing..."
    echo "Using backend config: $BACKEND_CONFIG"
    timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -input=false || {
      echo "Init failed for $d"
      continue
    }
    
    # Workspace with timeout
    echo "Step 2: Setting workspace..."
    timeout 30 terraform -chdir="$d" workspace select "$ENV" 2>/dev/null || \
    timeout 30 terraform -chdir="$d" workspace new "$ENV" || {
      echo "Workspace setup failed for $d"
      continue
    }
    
    PLAN="${ENV}.tfplan"
    echo "Step 3: Planning... Output: $PLAN"
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