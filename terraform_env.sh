#!/bin/bash
set -euo pipefail

ENV="${ATLANTIS_WORKSPACE:-staging}"
echo "Running Terraform workflow for environment: $ENV"

# If Atlantis provides changed files
CHANGED_FILES="${ATLANTIS_PULL_REQUEST_CHANGED_FILES:-}"

# Collect all unique application directories that contain main.tf
APP_DIRS=()

if [[ -n "$CHANGED_FILES" ]]; then
    while IFS= read -r file; do
        # Only consider files under application/*
        if [[ "$file" == application/* ]]; then
            dir=$(dirname "$file")
            # Walk up until we find main.tf
            while [[ "$dir" != "." && "$dir" != "/" ]]; do
                if [[ -f "$dir/main.tf" ]]; then
                    APP_DIRS+=("$dir")
                    break
                fi
                dir=$(dirname "$dir")
            done
        fi
    done <<< "$CHANGED_FILES"
else
    # Fallback: process all apps if no changed files provided
    while IFS= read -r dir; do
        [[ -f "$dir/main.tf" ]] && APP_DIRS+=("$dir")
    done < <(find application -mindepth 1 -maxdepth 1 -type d | sort)
fi

# Remove duplicates
APP_DIRS=($(printf "%s\n" "${APP_DIRS[@]}" | sort -u))

if [[ ${#APP_DIRS[@]} -eq 0 ]]; then
    echo "No application directories found with main.tf"
    exit 0
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

# Loop through each app directory
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
    while IFS= read -r PLAN; do
        terraform apply -input=false "$PLAN"
    done < "$PLANLIST"
else
    echo "No plan files to apply."
fi

echo "Terraform workflow completed for $ENV"
