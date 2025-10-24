#!/bin/bash
set -euo pipefail
ENV="$1"

# Find all application
mapfile -t dirs < <(find application -maxdepth 2 -name "main.tf" -type f | sed 's|/main.tf||' | sort -u)

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")
    echo "=== Planning $APP_NAME ($ENV) ==="
    
    case "$ENV" in
      "production")
        BACKEND_CONFIG="$d/env/production/prod.con"
        VAR_FILE="$d/config/production.tfvars"
        ;;
      "staging")
        BACKEND_CONFIG="$d/env/staging/stage.con"
        VAR_FILE="$d/config/stage.tfvars"
        ;;
    esac

    # Initialize
    if [[ -f "$BACKEND_CONFIG" ]]; then
      terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG"
    else
      terraform -chdir="$d" init -upgrade
    fi

    # Workspace
    terraform -chdir="$d" workspace select "$ENV" 2>/dev/null || terraform -chdir="$d" workspace new "$ENV"

    PLAN="/tmp/$(echo "$d" | tr "/" "_")_${ENV}.tfplan"

    # Plan
    if [[ -f "$VAR_FILE" ]]; then
      terraform -chdir="$d" plan -input=false -lock-timeout=20m -var-file="$VAR_FILE" -out="$PLAN"
    else
      terraform -chdir="$d" plan -input=false -lock-timeout=20m -out="$PLAN"
    fi

    echo "$PLAN" >> "$PLANLIST"
  fi
done