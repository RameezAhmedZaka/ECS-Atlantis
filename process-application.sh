#!/bin/bash
set -euo pipefail
ENV="$1"

echo "=== ULTIMATE DEBUG SCRIPT STARTED ==="
echo "Environment: $ENV"
echo "Working directory: $(pwd)"
echo "===="

# Find application
mapfile -t dirs < <(find application -maxdepth 2 -name "main.tf" -type f 2>/dev/null | sed 's|/main.tf||' | sort -u | head -2)

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "❌ CRITICAL: No application found!"
  echo "Directory structure:"
  find . -type d -name "application" -o -name "app*" 2>/dev/null | head -10
  exit 1
fi

echo "application to process: ${dirs[*]}"

for d in "${dirs[@]}"; do
  echo ""
  echo "====== PROCESSING $d ======"
  
  if [[ ! -f "$d/main.tf" ]]; then
    echo "❌ main.tf not found in $d"
    continue
  fi

  APP_NAME=$(basename "$d")
  echo "Application: $APP_NAME"
  
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

  echo "Backend config: $d/$BACKEND_CONFIG"
  echo "Var file: $d/$VAR_FILE"

  # CHECK 1: Do the config files exist?
  echo "=== CHECKING FILES ==="
  if [[ -f "$d/$BACKEND_CONFIG" ]]; then
    echo "✅ Backend config exists"
    echo "Backend config content:"
    cat "$d/$BACKEND_CONFIG"
  else
    echo "❌ Backend config MISSING: $d/$BACKEND_CONFIG"
    echo "Files in $d:"
    ls -la "$d/" 2>/dev/null || echo "Cannot list directory"
    continue
  fi

  if [[ -f "$d/$VAR_FILE" ]]; then
    echo "✅ Var file exists"
  else
    echo "❌ Var file MISSING: $d/$VAR_FILE"
    continue
  fi

  # CHECK 2: What's in the Terraform files?
  echo "=== TERRAFORM FILES ==="
  if [[ -f "$d/backend.tf" ]]; then
    echo "backend.tf:"
    cat "$d/backend.tf"
  else
    echo "❌ No backend.tf file found"
  fi

  # CHECK 3: Try init with FULL OUTPUT
  echo "=== TERRAFORM INIT ==="
  echo "Running: terraform -chdir=\"$d\" init -backend-config=\"$BACKEND_CONFIG\""
  
  # Capture ALL output including errors
  set +e
  INIT_OUTPUT=$(terraform -chdir="$d" init -backend-config="$BACKEND_CONFIG" -input=false 2>&1)
  INIT_EXIT_CODE=$?
  set -e
  
  echo "Init exit code: $INIT_EXIT_CODE"
  echo "Init output:"
  echo "$INIT_OUTPUT"
  
  if [[ $INIT_EXIT_CODE -ne 0 ]]; then
    echo "❌ INIT FAILED - This is the actual error above ↑"
    continue
  fi

  # CHECK 4: Workspace
  echo "=== WORKSPACE ==="
  set +e
  WORKSPACE_OUTPUT=$(terraform -chdir="$d" workspace select "$ENV" 2>&1)
  WORKSPACE_EXIT_CODE=$?
  set -e
  
  if [[ $WORKSPACE_EXIT_CODE -ne 0 ]]; then
    echo "Workspace select failed, creating new: $WORKSPACE_OUTPUT"
    terraform -chdir="$d" workspace new "$ENV" 2>&1
  else
    echo "✅ Workspace selected: $ENV"
  fi

  # CHECK 5: Plan
  echo "=== TERRAFORM PLAN ==="
  PLAN_FILE="/tmp/debug_${APP_NAME}_${ENV}.tfplan"
  echo "Plan file: $PLAN_FILE"
  
  set +e
  PLAN_OUTPUT=$(terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN_FILE" 2>&1)
  PLAN_EXIT_CODE=$?
  set -e
  
  echo "Plan exit code: $PLAN_EXIT_CODE"
  echo "Plan output (last 30 lines):"
  echo "$PLAN_OUTPUT" | tail -30
  
  if [[ $PLAN_EXIT_CODE -eq 0 ]]; then
    echo "✅ PLAN SUCCESSFUL"
    echo "$PLAN_FILE" >> "/tmp/atlantis_planfiles_${ENV}.lst"
  else
    echo "❌ PLAN FAILED"
  fi

  echo "====== FINISHED $d ======"
  echo ""
done

echo "=== SCRIPT COMPLETED ==="