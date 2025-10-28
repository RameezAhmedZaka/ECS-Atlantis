#!/bin/bash
set -euo pipefail
ENV="$1"
RAW_FILTER="${2:-}"  # Raw filter that might include flags

echo "=== STARTING $ENV at $(date) ==="

DESTROY_FLAG=false
APP_FILTER=""

IFS=',' read -ra ARGS <<< "$RAW_FILTER"
for arg in "${ARGS[@]}"; do
    arg_clean=$(echo "$arg" | xargs)
    case "$arg_clean" in
        -destroy|--destroy) DESTROY_FLAG=true ;;
        --) ;;  # ignore separator
        *)
            if [[ -n "$arg_clean" ]]; then
                APP_FILTER="$arg_clean"
            fi
            ;;
    esac
done

echo "Destroy flag: $DESTROY_FLAG"
echo "App filter: $APP_FILTER"

mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application found!"
  exit 1
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
> "$PLANLIST"
processed_count=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")

    # Skip apps from other environments (critical fix)
    case "$d" in
      *"staging"*)
        [[ "$ENV" != "staging" ]] && continue
        ;;
      *"production"*)
        [[ "$ENV" != "production" ]] && continue
        ;;
      *"helia"*)
        [[ "$ENV" != "helia" ]] && continue
        ;;
    esac

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
    esac

    if [[ ! -f "$d/$BACKEND_CONFIG" || ! -f "$d/$VAR_FILE" ]]; then
      echo "Missing backend or var file for $APP_NAME"
      continue
    fi

    rm -rf "$d/.terraform"

    echo "Initializing..."
    timeout 120 terraform -chdir="$d" init -upgrade -reconfigure \
      -backend-config="$BACKEND_CONFIG" -input=false || continue

    PLAN="/tmp/application_${APP_NAME}_${ENV}.tfplan"
    DESTROY_ARG=""
    [[ "$DESTROY_FLAG" == "true" ]] && DESTROY_ARG="-destroy"

    echo "Planning..."
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m \
      -var-file="$VAR_FILE" $DESTROY_ARG -out="$PLAN" || continue

    echo "$d|$PLAN" >> "$PLANLIST"
    ((processed_count++))
  fi
done

echo "=== COMPLETED PLAN for $ENV at $(date) ==="
echo "Plan files created for $processed_count apps:"
cat "$PLANLIST" || echo "No plan files created"
