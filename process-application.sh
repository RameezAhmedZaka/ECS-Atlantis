#!/bin/bash
set -euo pipefail
ENV="$1"
APP_FILTER="${2:-}"  # Optional app filter

echo "=== STARTING $ENV at $(date) ==="
if [[ -n "$APP_FILTER" ]]; then
  echo "Filtering for app: $APP_FILTER"
fi

# Find application directories
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No applications found!"
  exit 1
fi

echo "Found ${#dirs[@]} applications"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
processed_count=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")

    # Apply filter if provided
    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ==="
      continue
    fi

    echo "=== Planning $APP_NAME ($ENV) ==="
    
    # Set environment-specific files
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
    
    # Check if required files exist
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "Backend config not found: $d/$BACKEND_CONFIG"
      continue
    fi
    
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE"
      continue
    fi
    
    # Clean up and initialize
    rm -rf "$d/.terraform"
    
    echo "Step 1: Initializing..."
    timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -reconfigure \
      -input=false || {
      echo "Init failed for $d"
      continue
    }

    # Create unique plan file
    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    
    echo "Step 2: Planning... Output: $PLAN"
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
      echo "Plan failed for $d"
      continue
    }

    echo "$d|$PLAN" >> "$PLANLIST"
    ((processed_count++))
    echo "Successfully planned $APP_NAME"
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

# Summary
if [[ -n "$APP_FILTER" && $processed_count -eq 0 ]]; then
  echo "⚠️  No applications matched filter: $APP_FILTER"
  echo "Available applications:"
  for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
      APP_NAME=$(basename "$d")
      echo "  - $APP_NAME"
    fi
  done
else
  echo "Successfully processed $processed_count application(s) for $ENV"
fi

echo "=== COMPLETED $ENV at $(date) ==="
if [[ -f "$PLANLIST" ]]; then
  echo "Plan files created:"
  cat "$PLANLIST"
else
  echo "No plan files created"
fi