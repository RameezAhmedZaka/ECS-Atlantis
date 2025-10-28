#!/bin/bash
set -euo pipefail
ENV="$1"
RAW_FILTER="${2:-}"  # Raw filter that might include flags

# All human/debug output goes to stderr so it cannot accidentally be captured into the planlist.
echo "=== STARTING $ENV at $(date) ===" >&2

# Parse arguments to extract app name and detect destroy flag
DESTROY_FLAG=false
APP_FILTER=""

# Split the raw filter by commas
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

echo "Destroy flag: $DESTROY_FLAG" >&2
echo "App filter: $APP_FILTER" >&2

if [[ -n "$APP_FILTER" ]]; then
  echo "Filtering for app: $APP_FILTER" >&2
fi

# Find application directories
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application found!" >&2
  exit 1
fi

echo "Found ${#dirs[@]} application(s): ${dirs[*]}" >&2
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
processed_count=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")

    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ===" >&2
      continue
    fi

    echo "=== Planning $APP_NAME ($ENV) ===" >&2
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
        echo "Unknown ENV: $ENV" >&2
        continue
        ;;
    esac

    echo "Directory: $d" >&2
    echo "Backend config: $BACKEND_CONFIG" >&2
    echo "Var file: $VAR_FILE" >&2

    # Check if files exist
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "Backend config not found: $d/$BACKEND_CONFIG" >&2
      continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "Var file not found: $d/$VAR_FILE" >&2
      continue
    fi

    rm -rf "$d/.terraform"

    # Initialize with backend config
    echo "Step 1: Initializing..." >&2
    timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -reconfigure \
      -input=false || {
      echo "Init failed for $d" >&2
      continue
    }

    # Create unique plan file name
    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    echo "Step 3: Planning... Output: $PLAN" >&2

    # Add destroy flag if needed
    DESTROY_ARG=""
    if [[ "$DESTROY_FLAG" == "true" ]]; then
      DESTROY_ARG="-destroy"
      echo "DESTROY MODE ENABLED" >&2
    fi

    # Plan with var-file and optional destroy flag
    timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" $DESTROY_ARG -out="$PLAN" || {
      echo "Plan failed for $d" >&2
      continue
    }

    # Only the well-formed plan entry is written to the PLANLIST file.
    printf '%s|%s\n' "$d" "$PLAN" >> "$PLANLIST"
    echo "Successfully planned $APP_NAME" >&2
    processed_count=$((processed_count + 1))
  else
    echo "Skipping $d (main.tf missing)" >&2
  fi
done

if [[ -n "$APP_FILTER" && $processed_count -eq 0 ]]; then
  echo "⚠️  No applications matched filter: $APP_FILTER" >&2
  echo "Available applications:" >&2
  for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
      echo "  - $(basename "$d")" >&2
    fi
  done
fi

echo "=== COMPLETED $ENV at $(date) ===" >&2
echo "Plan files created (written to $PLANLIST):" >&2
# Print the planlist to stderr so it doesn't get captured if caller redirects stdout into the file.
cat "$PLANLIST" >&2 || echo "No plan files created" >&2