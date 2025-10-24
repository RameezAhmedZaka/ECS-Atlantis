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
        BACKEND_CONFIG="/env/production/prod.conf"
        VAR_FILE="$d/config/production.tfvars"
        ;;
      "staging")
        BACKEND_CONFIG="$d/env/staging/stage.conf"
        VAR_FILE="$d/config/stage.tfvars"
        ;;
    esac

    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG"
    echo "Var file: $VAR_FILE"

    # Initialize with better timeout and logging
    echo "Step 1: Initializing..."
    if [[ -f "$BACKEND_CONFIG" ]]; then
      echo "Using backend config: $BACKEND_CONFIG"
      timeout 120 terraform init -upgrade -backend-config="$BACKEND_CONFIG" -input=false || {
        echo "❌ Init failed for $d"
        continue
      }
    else
      echo "No backend config found, using default init"
      timeout 120 terraform -chdir="$d" init -upgrade -input=false || {
        echo "❌ Init failed for $d"
        continue
      }
    fi

    # Workspace with timeout
    echo "Step 2: Setting workspace..."
    timeout 30 terraform -chdir="$d" workspace select "$ENV" 2>/dev/null || \
    timeout 30 terraform -chdir="$d" workspace new "$ENV" || {
      echo "❌ Workspace setup failed for $d"
      continue
    }

    PLAN="/tmp/$(echo "$d" | tr "/" "_")_${ENV}.tfplan"
    echo "Step 3: Planning... Output: $PLAN"

    # Plan with better timeout and error handling
    if [[ -f "$VAR_FILE" ]]; then
      echo "Using var-file: $VAR_FILE"
      timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
        echo "❌ Plan failed for $d"
        continue
      }
    else
      echo "No var-file found, planning without it"
      timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -out="$PLAN" || {
        echo "❌ Plan failed for $d"
        continue
      }
    fi

    echo "$PLAN" >> "$PLANLIST"
    echo "✅ Successfully planned $APP_NAME"
    
  else
    echo "⚠️ Skipping $d (main.tf missing)"
  fi
done

echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"