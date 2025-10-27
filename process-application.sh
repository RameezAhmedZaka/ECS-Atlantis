#!/bin/bash
set -euo pipefail

MODE="${1:-plan}"  # plan or apply
PLANLIST="/tmp/atlantis_planfiles.lst"
: > "$PLANLIST"

# Use ATLANTIS_CHANGED_FILES if set, otherwise list all files in the PR
if [[ -n "${ATLANTIS_CHANGED_FILES:-}" ]]; then
    CHANGED_FILES="$ATLANTIS_CHANGED_FILES"
else
    # Safe git fetch to get main branch for comparison
    git fetch origin +refs/heads/*:refs/remotes/origin/*
    BASE_BRANCH="${ATLANTIS_BASE_BRANCH:-main}" # default to main
    CHANGED_FILES=$(git diff --name-only origin/$BASE_BRANCH...HEAD)
fi

echo "Changed files:"
echo "$CHANGED_FILES"

# Detect if main.tf changed anywhere
MAIN_CHANGED=false
if echo "$CHANGED_FILES" | grep -q "main.tf"; then
  MAIN_CHANGED=true
fi

# Iterate all apps
for APP_DIR in application/*; do
  [[ -d "$APP_DIR" ]] || continue
  APP_NAME=$(basename "$APP_DIR")

  # Determine environments to plan
  ENVS=()
  if $MAIN_CHANGED; then
    ENVS=("staging" "production")
  else
    for ENV in staging production; do
      if echo "$CHANGED_FILES" | grep -q "^$APP_DIR/config/$ENV"; then
        ENVS+=("$ENV")
      fi
    done
  fi

  [[ ${#ENVS[@]} -gt 0 ]] || continue

  for ENV in "${ENVS[@]}"; do
    BACKEND_CONFIG="$APP_DIR/env/$ENV/${ENV:0:4}.conf" # prod.conf or stag.conf
    VAR_FILE="$APP_DIR/config/${ENV}.tfvars"

    [[ -f "$APP_DIR/main.tf" ]] || { echo "Skipping $APP_NAME (main.tf missing)"; continue; }
    [[ -f "$BACKEND_CONFIG" ]] || { echo "Backend config missing for $APP_NAME $ENV"; continue; }
    [[ -f "$VAR_FILE" ]] || { echo "Var file missing for $APP_NAME $ENV"; continue; }

    rm -rf "$APP_DIR/.terraform"
    echo "=== Planning $APP_NAME ($ENV) ==="
    PLAN_FILE="/tmp/${APP_NAME}_${ENV}.tfplan"

    terraform -chdir="$APP_DIR" init -upgrade -reconfigure -backend-config="$BACKEND_CONFIG" -input=false
    terraform -chdir="$APP_DIR" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" -out="$PLAN_FILE"

    echo "$APP_DIR|$PLAN_FILE" >> "$PLANLIST"
  done
done

echo "Plans ready:"
cat "$PLANLIST"
