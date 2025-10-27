#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <staging|production|helia|all> [app-path]
  If run from inside an app directory containing main.tf, you can omit app-path.
  If app-path is provided it can be a single app dir (e.g. application/apollo) or omitted to process all apps.
EOF
  exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

ENV="$1"
TARGET_DIR="${2:-}"

# Which envs to process
declare -a ALL_ENVS=("staging" "production" "helia")

if [[ "$ENV" == "all" ]]; then
  ENVS=("${ALL_ENVS[@]}")
else
  ENVS=("$ENV")
fi

# Determine list of app directories to process:
# If a path arg is provided, use that.
# If current dir contains main.tf, treat it as a single app.
# Otherwise find all apps under application/* that contain main.tf.
mapfile -t DIRS < <(
  if [[ -n "$TARGET_DIR" ]]; then
    if [[ -f "$TARGET_DIR/main.tf" ]]; then
      printf '%s\n' "$TARGET_DIR"
    else
      echo "Given app path does not contain main.tf: $TARGET_DIR" >&2
      exit 1
    fi
  elif [[ -f "main.tf" ]]; then
    printf '%s\n' "$(pwd)"
  else
    find application -maxdepth 2 -type f -name "main.tf" -printf '%h\n' 2>/dev/null | sort -u
  fi
)

if [[ ${#DIRS[@]} -eq 0 ]]; then
  echo "No application directories found to plan."
  exit 1
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

echo "=== STARTING PLANNING (ENV=$ENV) at $(date) ==="
echo "Planning ${#DIRS[@]} app(s): ${DIRS[*]}"

for d in "${DIRS[@]}"; do
  if [[ ! -d "$d" ]]; then
    echo "Skipping invalid directory: $d"
    continue
  fi

  APP_NAME=$(basename "$d")

  for e in "${ENVS[@]}"; do
    echo "---- App: $APP_NAME  Env: $e ----"

    # Map env to backend config and var file names (relative to app dir)
    case "$e" in
      production)
        BACKEND_CONFIG="env/production/prod.conf"
        VAR_FILE="config/production.tfvars"
        ;;
      staging)
        BACKEND_CONFIG="env/staging/stage.conf"
        VAR_FILE="config/stage.tfvars"
        ;;
      helia)
        BACKEND_CONFIG="env/helia/helia.conf"
        VAR_FILE="config/helia.tfvars"
        ;;
      *)
        echo "Unknown environment: $e" >&2
        continue
        ;;
    esac

    # Validate files
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "Backend config not found: $d/$BACKEND_CONFIG -- skipping"
      continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE -- skipping"
      continue
    fi

    # Clean local .terraform to avoid state issues
    rm -rf "$d/.terraform" || true

    echo "Initializing terraform in $d for env $e (backend: $BACKEND_CONFIG)"
    # Use -chdir so backend-config path should be passed relative to repo root or absolute.
    # We'll pass the absolute backend config path for clarity.
    ABS_BACKEND_CONF="$(realpath "$d/$BACKEND_CONFIG")"
    if ! timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$ABS_BACKEND_CONF" -reconfigure -input=false; then
      echo "Init failed for $d (env $e), skipping"
      continue
    fi

    PLAN_FILE="/tmp/${APP_NAME}_${e}.tfplan"
    echo "Planning (output -> $PLAN_FILE) with var-file: $VAR_FILE"
    if ! timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$d/$VAR_FILE" -out="$PLAN_FILE"; then
      echo "Plan FAILED for $d (env $e), skipping"
      continue
    fi

    # Use absolute path for plan in the plan list so apply can find it regardless of PWD
    ABS_PLAN="$(realpath "$PLAN_FILE")"
    echo "${d}|${ABS_PLAN}" >> "$PLANLIST"
    echo "Planned $APP_NAME ($e): $ABS_PLAN"
  done
done

echo "=== COMPLETED PLANNING (ENV=$ENV) at $(date) ==="
echo "Plan list: $PLANLIST"
cat "$PLANLIST" 2>/dev/null || echo "No plans recorded"