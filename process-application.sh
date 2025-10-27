#!/bin/bash
set -euo pipefail

ENV="$1"
APP_FILTER="${2:-}"  # Optional: second parameter is app name

echo "=== STARTING $ENV at $(date) ==="

# Find all applications
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)

# If APP_FILTER is set, filter only that app
if [[ -n "$APP_FILTER" ]]; then
  dirs=($(printf "%s\n" "${dirs[@]}" | grep "/$APP_FILTER$"))
fi

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application found!"
  exit 1
fi

echo "Found ${#dirs[@]} application(s): ${dirs[*]}"
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
      "helia")
        BACKEND_CONFIG="env/helia/helia.conf"
        VAR_FILE="config/helia.tfvars"
        ;;
      *)
        echo "Unknown ENV: $ENV"
        continue
        ;;
    esac

    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "Backend config not found: $d/$BACKEND_CONFIG"
      continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE"
      continue
    fi

    rm -rf "$d/.terraform"
    echo "Step 1: Initializing..."
    timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG" -reconfigure -input=false || {
      echo "Init failed for $d"
      continue
    }

    PLAN="/tmp/${APP_NAME}_${ENV}.tfplan"
    echo "Step 2: Planning... Output: $PLAN"
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN" || {
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
