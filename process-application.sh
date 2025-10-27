#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <env> [app_dir]
  env: staging | production | helia
  app_dir (optional): path to a single app directory under application/ (e.g. application/adot)
EOF
  exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

ENV="$1"
TARGET_APP="${2:-}"

echo "=== STARTING processing for env='$ENV' target='$TARGET_APP' at $(date) ==="

# collect app directories
if [[ -n "$TARGET_APP" ]]; then
  if [[ -d "$TARGET_APP" ]]; then
    dirs=("$TARGET_APP")
  else
    echo "Target app directory not found: $TARGET_APP"
    exit 1
  fi
else
  mapfile -t dirs < <(find application -type f -name "main.tf" -printf '%h\n' | sort -u)
fi

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application directories found!"
  exit 1
fi

echo "Found ${#dirs[@]} application(s): ${dirs[*]}"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for d in "${dirs[@]}"; do
  if [[ ! -f "$d/main.tf" ]]; then
    echo "Skipping $d (main.tf missing)"
    continue
  fi

  APP_NAME=$(basename "$d")
  echo "=== Planning $APP_NAME ($ENV) ==="
  # Resolve backend config file (search env/<ENV>/*.conf)
  BACKEND_CONFIG_PATH=$(find "$d/env/$ENV" -maxdepth 1 -type f -name "*.conf" -print -quit 2>/dev/null || true)
  if [[ -z "$BACKEND_CONFIG_PATH" ]]; then
    echo "Backend config not found under $d/env/$ENV"
    echo "Available backend configs for $d:"
    find "$d/env" -type f -name "*.conf" 2>/dev/null || echo "No backend configs found at all for $d"
    continue
  fi

  # Resolve var-file: staging uses stage.tfvars in your tree, others use <env>.tfvars
  if [[ "$ENV" == "staging" ]]; then
    VAR_FILE_REL="config/stage.tfvars"
  else
    VAR_FILE_REL="config/${ENV}.tfvars"
  fi

  if [[ ! -f "$d/$VAR_FILE_REL" ]]; then
    echo "Var file not found: $d/$VAR_FILE_REL"
    ls -la "$d/config" 2>/dev/null || echo "config directory not found for $d"
    continue
  fi

  # Clean slate for init
  rm -rf "$d/.terraform" || true

  echo "Step 1: Initializing $d using backend config: $BACKEND_CONFIG_PATH"
  if ! timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG_PATH" -reconfigure -input=false; then
    echo "Init failed for $d"
    continue
  fi

  # Create a unique plan file in /tmp so we don't overwrite across directories
  PLAN="/tmp/$(echo "$d" | sed 's|/|_|g')_${ENV}.tfplan"
  echo "Step 2: Planning $d -> $PLAN (var-file: $VAR_FILE_REL)"
  if ! timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$d/$VAR_FILE_REL" -out="$PLAN"; then
    echo "Plan failed for $d"
    continue
  fi

  # record directory + absolute plan path
  echo "$d|$PLAN" >> "$PLANLIST"
  echo "Successfully planned $APP_NAME ($ENV) -> $PLAN"
done

echo "=== COMPLETED processing for env='$ENV' at $(date) ==="
echo "Plan list created: $PLANLIST"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"