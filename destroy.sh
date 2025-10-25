#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING DESTROY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]]; then
  echo "No plan list found: $PLANLIST"
  exit 1
fi

if [[ ! -s "$PLANLIST" ]]; then
  echo "Plan list is empty: $PLANLIST"
  exit 1
fi

echo "Destroying application from: $PLANLIST"
cat "$PLANLIST"

# Loop through each directory from the plan list
while IFS='|' read -r d PLAN; do
  if [[ -d "$d" ]]; then
    APP_NAME=$(basename "$d")
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

    echo "=== Destroying $APP_NAME ($ENV) in directory $d ==="

    # Initialize backend
    timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -input=false || {
      echo "Init failed for $d"
      continue
    }

    # Ensure default workspace
    timeout 30 terraform -chdir="$d" workspace select default 2>/dev/null || \
    timeout 30 terraform -chdir="$d" workspace new default || {
      echo "Workspace setup failed for $d"
      continue
    }

    # Destroy resources
    timeout 600 terraform -chdir="$d" destroy -input=false -auto-approve -var-file="$VAR_FILE" || {
      echo ":x: Destroy failed for $APP_NAME"
      continue
    }

    echo "Successfully destroyed $APP_NAME"

  else
    echo "Directory not found: $d"
  fi
done < "$PLANLIST"

# Optionally remove the plan list file
rm -f "$PLANLIST"
echo "=== DESTROY COMPLETED for $ENV at $(date) ==="
