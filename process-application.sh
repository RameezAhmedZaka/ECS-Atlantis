#!/bin/bash
set -euo pipefail
ENV="$1"
APP_NAME="$2"  # Now we get app name as parameter from Atlantis

echo "=== STARTING $APP_NAME $ENV at $(date) ==="

# Define the application directory
APP_DIR="application/$APP_NAME"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Application directory not found: $APP_DIR"
  exit 1
fi

if [[ ! -f "$APP_DIR/main.tf" ]]; then
  echo "main.tf not found in: $APP_DIR"
  exit 1
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
# Ensure planlist file exists
touch "$PLANLIST"

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

echo "Directory: $APP_DIR"
echo "Backend config: $BACKEND_CONFIG"
echo "Var file: $VAR_FILE"

# Check if files exist
if [[ ! -f "$APP_DIR/$BACKEND_CONFIG" ]]; then
  echo "Backend config not found: $APP_DIR/$BACKEND_CONFIG"
  exit 1
fi

if [[ ! -f "$APP_DIR/$VAR_FILE" ]]; then
  echo "Var file not found: $APP_DIR/$VAR_FILE"
  exit 1
fi

# Initialize with backend config
echo "Step 1: Initializing..."
timeout 120 terraform -chdir="$APP_DIR" init -upgrade -backend-config="$BACKEND_CONFIG" -input=false || {
  echo "Init failed for $APP_DIR"
  exit 1
}

# Workspace with timeout
echo "Step 2: Setting workspace..."
timeout 30 terraform -chdir="$APP_DIR" workspace select "$ENV" 2>/dev/null || \
timeout 30 terraform -chdir="$APP_DIR" workspace new "$ENV" || {
  echo "Workspace setup failed for $APP_DIR"
  exit 1
}

PLAN="${ENV}.tfplan"
echo "Step 3: Planning... Output: $PLAN"
timeout 300 terraform -chdir="$APP_DIR" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
  echo "Plan failed for $APP_DIR"
  exit 1
}

# Store both directory and plan path
echo "$APP_DIR|$PLAN" >> "$PLANLIST"
echo "Successfully planned $APP_NAME"

echo "=== COMPLETED $APP_NAME $ENV at $(date) ==="