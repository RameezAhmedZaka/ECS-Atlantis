#!/bin/bash
set -euo pipefail

# Use the Atlantis workspace
ENV="${ATLANTIS_WORKSPACE:-staging}"
echo "Running Terraform workflow for environment: $ENV"

# Always start from the repo root
BASE_DIR="${BASE_DIR:-.}"  # ensure we can override if needed

# Scan all applications with main.tf
APP_DIRS=()
for d in "$BASE_DIR"/application/*; do
    [[ -f "$d/main.tf" ]] && APP_DIRS+=("$d")
done

if [[ ${#APP_DIRS[@]} -eq 0 ]]; then
    echo "No applications found with main.tf under $BASE_DIR/application"
    exit 0
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for APP in "${APP_DIRS[@]}"; do
    APP_NAME=$(basename "$APP")
    echo "=== Processing $APP_NAME ($ENV) ==="

    if [[ "$ENV" == "staging" ]]; then
        BACKEND="$APP/env/staging/stage.con"
        VAR_FILE="$APP/config/stage.tfvars"
    else
        BACKEND="$APP/env/production/prod.con"
        VAR_FILE="$APP/config/production.tfvars"
    fi

    # Terraform init
    if [[ -f "$BACKEND" ]]; then
        terraform -chdir="$APP" init -upgrade -backend-config="$BACKEND"
    else
        terraform -chdir="$APP" init -upgrade
    fi

    terraform -chdir="$APP" workspace select "$ENV" 2>/dev/null || \
        terraform -chdir="$APP" workspace new "$ENV"

    PLAN="/tmp/${APP_NAME}_${ENV}.tfplan"
    if [[ -f "$VAR_FILE" ]]; then
        terraform -chdir="$APP" plan -input=false -lock-timeout=20m -var-file="$VAR_FILE" -out="$PLAN"
    else
        terraform -chdir="$APP" plan -input=false -lock-timeout=20m -out="$PLAN"
    fi

    echo "$PLAN" >> "$PLANLIST"
done

# Apply
if [[ -s "$PLANLIST" ]]; then
    for PLAN in $(cat "$PLANLIST"); do
        terraform apply -input=false "$PLAN"
    done
else
    echo "No plan files to apply."
fi

echo "Terraform workflow completed for $ENV"
