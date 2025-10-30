#!/bin/bash
set -euo pipefail
ENV="$1"
RAW_FILTER="${2:-}"

echo "=== STARTING $ENV for project: $ATLANTIS_PROJECT ==="

# Extract app name from project name (e.g., "app1-staging" -> "app1")
APP_NAME=$(echo "$ATLANTIS_PROJECT" | sed 's/-staging//' | sed 's/-production//' | sed 's/-helia//')
APP_DIR="application/$APP_NAME"

echo "Processing application: $APP_NAME in directory: $APP_DIR"

if [ ! -f "$APP_DIR/main.tf" ]; then
  echo "Error: Application directory $APP_DIR not found or missing main.tf"
  exit 1
fi

# Your existing processing logic here, but for single app
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
esac

echo "Backend config: $BACKEND_CONFIG"
echo "Var file: $VAR_FILE"

# Initialize
rm -rf "$APP_DIR/.terraform"
timeout 120 terraform -chdir="$APP_DIR" init -upgrade \
  -backend-config="$BACKEND_CONFIG" \
  -reconfigure \
  -input=false || {
  echo "Init failed for $APP_DIR"
  exit 1
}

# Create plan
PLAN_NAME="${APP_NAME}_${ENV}.tfplan"
PLAN="/tmp/${PLAN_NAME}"
PLAN_OUTPUT="/tmp/plan_output_${APP_NAME}_${ENV}.txt"

timeout 300 terraform -chdir="$APP_DIR" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" 2>&1 | tee "$PLAN_OUTPUT" || {
  echo "Plan failed for $APP_DIR"
  exit 1
}

# Update changed apps list
CHANGED_APPS_LIST="/tmp/atlantis_changed_apps_${ENV}.lst"
if grep -q "No changes." "$PLAN_OUTPUT"; then
  echo "✅ No changes for $APP_NAME"
  # Ensure file exists but empty if no changes
  : > "$CHANGED_APPS_LIST"
else
  echo "🔄 Changes detected for $APP_NAME"
  echo "$APP_NAME" > "$CHANGED_APPS_LIST"
fi

rm -f "$PLAN_OUTPUT"
echo "=== COMPLETED $ENV for $APP_NAME at $(date) ==="