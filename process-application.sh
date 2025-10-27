#!/bin/bash
set -euo pipefail

ENV="$1"
RAW_FILTER="${2:-}"  # Optional, could be empty

echo "=== STARTING $ENV at $(date) ==="

# Parse arguments to extract app name and detect destroy flag
DESTROY_FLAG=false
APP_FILTER=""

# Split the raw filter by commas (or single app name)
IFS=',' read -ra ARGS <<< "$RAW_FILTER"
for arg in "${ARGS[@]}"; do
    arg_clean=$(echo "$arg" | xargs)  # Trim whitespace
    case "$arg_clean" in
        -destroy|--destroy)
            DESTROY_FLAG=true
            ;;
        --)
            # Skip separator
            ;;
        *)
            if [[ -n "$arg_clean" && "$arg_clean" != "-destroy" && "$arg_clean" != "--destroy" ]]; then
                APP_FILTER="$arg_clean"
            fi
            ;;
    esac
done

echo "Destroy flag: $DESTROY_FLAG"
echo "App filter: ${APP_FILTER:-ALL}"

# Find all application directories
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No applications found!"
  exit 1
fi

echo "Found ${#dirs[@]} application(s): ${dirs[*]}"

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
processed_count=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")

    # Apply filter if set
    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ==="
      continue
    fi

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
        echo "Unknown environment: $ENV"
        continue
        ;;
    esac

    # Check if backend/var files exist
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
    timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -reconfigure \
      -input=false || { echo "Init failed for $d"; continue; }

    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    echo "Step 2: Planning... Output: $PLAN"

    DESTROY_ARG=""
    if [[ "$DESTROY_FLAG" == "true" ]]; then
      DESTROY_ARG="-destroy"
      echo "DESTROY MODE ENABLED"
    fi

    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" $DESTROY_ARG -out="$PLAN" || {
      echo "Plan failed for $d"
      continue
    }

    echo "$d|$PLAN" >> "$PLANLIST"
    echo "Successfully planned $APP_NAME"
    ((processed_count++))
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

# Warn if filter applied but no matches found
if [[ -n "$APP_FILTER" && $processed_count -eq 0 ]]; then
  echo "⚠️  No applications matched filter: $APP_FILTER"
  echo "Available applications:"
  for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
      echo "  - $(basename "$d")"
    fi
  done
fi

echo "=== COMPLETED $ENV at $(date) ==="
echo "Plan files created:"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"
