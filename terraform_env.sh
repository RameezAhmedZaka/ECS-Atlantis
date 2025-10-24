#!/bin/bash
set -euo pipefail

# Determine the environment from Atlantis workspace
ENV="${ATLANTIS_WORKSPACE:-staging}"  # default to staging if not set
echo "Running Terraform workflow for environment: $ENV"

# Directory where applications are located
BASE_DIR="application"

# Collect all apps with a main.tf
APP_DIRS=()
while IFS= read -r dir; do
    [[ -f "$dir/main.tf" ]] && APP_DIRS+=("$dir")
done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#APP_DIRS[@]} -eq 0 ]]; then
    echo "No applications found with main.tf under $BASE_DIR"
    exit 0
fi

# Prepare plan list
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

# Loop over each application
for APP in "${APP_DIRS[@]}"; do
    APP_NAME=$(basename "$APP")
    echo "=== Processing $APP_NAME ($ENV) ==="

    # Backend config and var-file per environment
    if [[ "$ENV" == "staging" ]]; then
        BACKEND="$APP/env/staging/stage.con"
        VAR_FILE="$APP/config/stage.tfvars"
    else
        BACKEND="$APP/env/production/prod.con"
        VAR_FILE="$APP/config/production.tfvars"
    fi

    # Terraform init
    if [[ -f "$BACKEND" ]]; then
        echo "Initializing Terraform for $APP_NAME with backend $BACKEND"
        terraform -chdir="$APP" init -upgrade -backend-config="$BACKEND"
    else
        echo "Warning: Backend config $BACKEND not found, initializing without backend"
        terraform -chdir="$APP" init -upgrade
    fi

    # Workspace selection
    terraform -chdir="$APP" workspace select "$ENV" 2>/dev/null || \
        terraform -chdir="$APP" workspace new "$ENV"

    # Terraform plan
    PLAN="/tmp/${APP_NAME}_${ENV}.tfplan"
    if [[ -f "$VAR_FILE" ]]; then
        echo "Planning $APP_NAME with var-file $VAR_FILE"
        terraform -chdir="$APP" plan -input=false -lock-timeout=20m -var-file="$VAR_FILE" -out="$PLAN"
    else
        echo "Warning: Var-file $VAR_FILE not found, planning without it"
        terraform -chdir="$APP" plan -input=false -lock-timeout=20m -out="$PLAN"
    fi

    # Record plan for apply
    echo "$PLAN" >> "$PLANLIST"
done

# Terraform apply
if [[ -s "$PLANLIST" ]]; then
    echo "Applying all plans for environment: $ENV"
    while IFS= read -r PLAN; do
        echo "=== Applying $PLAN ==="
        terraform apply -input=false "$PLAN"
    done < "$PLANLIST"
else
    echo "No plan files found, nothing to apply."
fi

echo "Terraform workflow completed for environment: $ENV"
