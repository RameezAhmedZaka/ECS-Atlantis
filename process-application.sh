#!/bin/bash
set -euo pipefail
ENV="$1"
shift  # Remove the first argument (ENV), pass the rest

# Check if destroy flag is present
DESTROY_FLAG=""
for arg in "$@"; do
    if [[ "$arg" == "-destroy" ]]; then
        DESTROY_FLAG="-destroy"
        break
    fi
done

echo "=== STARTING $ENV at $(date) ==="
echo "Destroy flag: ${DESTROY_FLAG:--none}"

# Find application but limit to 2 for testing
mapfile -t dirs < <(find application -maxdepth 2 -name "main.tf" -type f | sed 's|/main.tf||' | sort -u | head -2)
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
        BACKEND_CONFIG="env/production/prod.conf"  # Relative to app directory
        VAR_FILE="config/production.tfvars"        # Relative to app directory
        ;;
      "staging")
        BACKEND_CONFIG="env/staging/stage.conf"    # Relative to app directory
        VAR_FILE="config/stage.tfvars"             # Relative to app directory
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
    # Initialize with backend config (ALWAYS use -chdir for consistency)
    echo "Step 1: Initializing..."
    echo "Using backend config: $BACKEND_CONFIG"
    timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -input=false || {
      echo "Init failed for $d"
      continue
    }
    # Workspace with timeout
    echo "Step 2: Setting workspace..."
    timeout 30 terraform -chdir="$d" workspace select default 2>/dev/null || \
    timeout 30 terraform -chdir="$d" workspace new default || {
      echo "Workspace setup failed for $d"
      continue
    }
    
    # Modify plan name for destroy plans
    if [[ -n "$DESTROY_FLAG" ]]; then
        PLAN="${ENV}_destroy.tfplan"
    else
        PLAN="${ENV}.tfplan"
    fi
    
    echo "Step 3: Planning... Output: $PLAN"
    echo "Using var-file: $VAR_FILE"
    
    # Add destroy flag to plan command if present
    if [[ -n "$DESTROY_FLAG" ]]; then
        timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" $DESTROY_FLAG || {
          echo "Destroy plan failed for $d"
          continue
        }
    else
        timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
          echo "Plan failed for $d"
          continue
        }
    fi
    
    echo "$d|$PLAN" >> "$PLANLIST"
    echo "Successfully planned $APP_NAME"
  else
    echo "Skipping $d (main.tf missing)"
  fi
done
echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"