#!/bin/bash
set -euo pipefail
ENV="$1"

echo "=== STARTING $ENV at $(date) ==="

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
      echo ":x: Backend config not found: $d/$BACKEND_CONFIG"
      ls -la "$d/env/" 2>/dev/null || echo "env directory not found"
      continue
    fi
    
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo ":x: Var file not found: $d/$VAR_FILE" 
      ls -la "$d/config/" 2>/dev/null || echo "config directory not found"
      continue
    fi

    # Initialize with backend config (ALWAYS use -chdir for consistency)
    echo "Step 1: Initializing..."
    echo "Using backend config: $BACKEND_CONFIG"
    timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -input=false || {
      echo ":x: Init failed for $d"
      continue
    }

    # FIX: Use environment-specific workspace instead of forcing "default"
    echo "Step 2: Setting workspace to $ENV..."
    timeout 30 terraform -chdir="$d" workspace select "$ENV" 2>/dev/null || {
      echo "Workspace $ENV not found, creating it..."
      timeout 30 terraform -chdir="$d" workspace new "$ENV"
    }

    PLAN="/tmp/$(echo "$d" | tr "/" "_")_${ENV}.tfplan"
    echo "Step 3: Planning... Output: $PLAN"

    # Plan with var-file
    echo "Using var-file: $VAR_FILE"
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
      echo ":x: Plan failed for $d"
      continue
    }

    # Store the directory along with plan path for apply
    echo "$d|$PLAN" >> "$PLANLIST"
    echo ":white_check_mark: Successfully planned $APP_NAME"
    
  else
    echo ":warning: Skipping $d (main.tf missing)"
  fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"