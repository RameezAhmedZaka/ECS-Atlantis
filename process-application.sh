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
      continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE"
      continue
    fi
    
    # CLEAN APPROACH: Remove existing terraform config to ensure clean slate
    echo "Step 1: Cleaning existing configuration..."
    rm -rf "$d/.terraform" "$d/.terraform.lock.hcl" 2>/dev/null || true
    
    # VERIFY backend config content
    echo "Backend config content:"
    cat "$d/$BACKEND_CONFIG"
    echo "---"
    
    # INIT with explicit backend config
    echo "Step 2: Initializing with exact backend path..."
    timeout 120 terraform -chdir="$d" init \
      -reconfigure \
      -backend-config="$BACKEND_CONFIG" \
      -input=false || {
      echo "Init failed for $d"
      continue
    }
    
    # VERIFY the backend was configured correctly
    echo "Step 3: Verifying backend configuration..."
    if [[ -f "$d/.terraform/terraform.tfstate" ]]; then
      echo "Backend configuration in state file:"
      grep -A5 -B5 '"backend":' "$d/.terraform/terraform.tfstate" | head -20 || echo "Could not extract backend info"
    fi
    
    # WORKSPACE setup
    echo "Step 4: Setting workspace..."
    timeout 30 terraform -chdir="$d" workspace select "$ENV" 2>/dev/null || \
    timeout 30 terraform -chdir="$d" workspace new "$ENV" || {
      echo "Workspace setup failed for $d"
      continue
    }
    
    echo "Current workspace: $(terraform -chdir="$d" workspace show)"
    
    # PLAN
    PLAN="${ENV}.tfplan"
    echo "Step 5: Planning... Output: $PLAN"
    
    timeout 300 terraform -chdir="$d" plan \
      -input=false \
      -lock-timeout=5m \
      -var-file="$VAR_FILE" \
      -out="$PLAN" || {
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