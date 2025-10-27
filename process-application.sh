#!/bin/bash
set -euo pipefail

# Usage: ./process-application.sh <environment>
ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 2
fi

echo "=== STARTING PLANNING for $ENV at $(date) ==="

# Find application directories that contain main.tf
mapfile -t dirs < <(find application -type f -name "main.tf" -print0 | xargs -0 -n1 dirname | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application main.tf files found under application/ - nothing to plan."
  exit 0
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for d in "${dirs[@]}"; do
  if [[ ! -f "$d/main.tf" ]]; then
    echo "Skipping $d: main.tf not present"
    continue
  fi

  APP_NAME=$(basename "$d")
  echo "=== Preparing plan for app: $APP_NAME (dir: $d) for env: $ENV ==="

  case "$ENV" in
    production)
      BACKEND_CONFIG="env/production/prod.conf"
      VAR_FILE="config/production.tfvars"
      ;;
    staging)
      BACKEND_CONFIG="env/staging/stage.conf"
      VAR_FILE="config/stage.tfvars"
      ;;
    *)
      echo "Unknown environment: $ENV"
      continue
      ;;
  esac

  # Verify backend config and var file exist
  if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
    echo "  -> Skipping $APP_NAME: backend config not found at $d/$BACKEND_CONFIG"
    continue
  fi
  if [[ ! -f "$d/$VAR_FILE" ]]; then
    echo "  -> Skipping $APP_NAME: var file not found at $d/$VAR_FILE"
    continue
  fi

  # Remove previous terraform state dir to avoid mismatches (optional)
  rm -rf "$d/.terraform" 2>/dev/null || true

  # Initialize with backend config. Using -chdir ensures paths resolve inside app dir.
  echo "  -> Initializing Terraform for $APP_NAME"
  if ! timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -reconfigure -input=false; then
    echo "  -> Init failed for $APP_NAME, skipping."
    continue
  fi

  # Create a unique plan filename in /tmp using sanitized directory path
  SANITIZED_DIR=$(echo "$d" | sed 's|/|_|g' | sed 's|^_||')
  PLAN="/tmp/${SANITIZED_DIR}_${ENV}.tfplan"

  echo "  -> Planning $APP_NAME -> plan: $PLAN (var-file: $VAR_FILE)"
  if ! timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN"; then
    echo "  -> Plan failed for $APP_NAME, skipping."
    rm -f "$PLAN" 2>/dev/null || true
    continue
  fi

  # Record directory + plan for later apply
  echo "${d}|${PLAN}" >> "$PLANLIST"
  echo "  -> Plan successful for $APP_NAME"
done

echo "=== COMPLETED PLANNING for $ENV at $(date) ==="
echo "Plan list file: $PLANLIST"
cat "$PLANLIST" || echo "(empty)"