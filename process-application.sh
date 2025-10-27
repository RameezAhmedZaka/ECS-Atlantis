#!/bin/bash
set -euo pipefail
ENV="$1"
RAW_FILTER="${2:-}"  # Raw filter that might include flags

echo "=== STARTING $ENV at $(date) ==="

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

echo "Destroy flag: $DESTROY_FLAG"
echo "App filter: $APP_FILTER"

if [[ -n "$APP_FILTER" ]]; then
  echo "Filtering for app: $APP_FILTER"
fi

# Find application directories
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application found!"
  exit 1
fi

echo "Found ${#dirs[@]} application: ${dirs[*]}"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
processed_count=0
success_count=0
fail_count=0
skipped_count=0

for d in "${dirs[@]}"; do
  if [[ -f "$d/main.tf" ]]; then
    APP_NAME=$(basename "$d")

    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ==="
      ((skipped_count++))
      continue
    fi

    echo "=== Processing $APP_NAME ($ENV) ==="
    
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
        echo "❌ Unknown environment: $ENV"
        exit 1
        ;;
    esac
    
    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG"
    echo "Var file: $VAR_FILE"
    
    # Check if files exist
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
      echo "❌ Backend config not found: $d/$BACKEND_CONFIG"
      ((fail_count++))
      continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
      echo "❌ Var file not found: $d/$VAR_FILE"
      ((fail_count++))
      continue
    fi
    
    rm -rf "$d/.terraform"
    
    # Initialize with backend config
    echo "Step 1: Initializing $APP_NAME..."
    if ! timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -reconfigure \
      -input=false; then
      echo "❌ Init failed for $APP_NAME"
      ((fail_count++))
      continue
    fi

    # Create unique plan file name
    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    echo "Step 2: Planning $APP_NAME... Output: $PLAN"
    
    # Add destroy flag if needed
    DESTROY_ARG=""
    if [[ "$DESTROY_FLAG" == "true" ]]; then
      DESTROY_ARG="-destroy"
      echo "DESTROY MODE ENABLED for $APP_NAME"
    fi
    
    # Plan with var-file and optional destroy flag
    if ! timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE" $DESTROY_ARG -out="$PLAN"; then
      echo "❌ Plan failed for $APP_NAME"
      ((fail_count++))
      continue
    fi

    echo "$d|$PLAN" >> "$PLANLIST"
    echo "✅ Successfully planned $APP_NAME"
    ((success_count++))
    ((processed_count++))
  else
    echo "⚠️  Skipping $d (main.tf missing)"
    ((skipped_count++))
  fi
done

echo ""
echo "=== SUMMARY ==="
echo "✅ Successful: $success_count"
echo "❌ Failed: $fail_count" 
echo "Skipped: $skipped_count"
echo "Total processed: $processed_count"

# Show available apps if filter was used but nothing matched
if [[ -n "$APP_FILTER" && $processed_count -eq 0 ]]; then
  echo ""
  echo "⚠️  No applications matched filter: $APP_FILTER"
  echo "Available applications:"
  for d in "${dirs[@]}"; do
    if [[ -f "$d/main.tf" ]]; then
      echo "  - $(basename "$d")"
    fi
  done
fi

# Only fail completely if ALL apps failed or no apps were processed
if [[ $success_count -eq 0 && $processed_count -gt 0 ]]; then
  echo ""
  echo "❌ CRITICAL: All applications failed!"
  echo "=== COMPLETED $ENV with FAILURES at $(date) ==="
  exit 1
elif [[ $success_count -eq 0 && $processed_count -eq 0 ]]; then
  echo ""
  echo "⚠️  No applications were processed"
  echo "=== COMPLETED $ENV with NO PROCESSED APPLICATIONS at $(date) ==="
  exit 1
else
  echo ""
  echo "=== COMPLETED $ENV at $(date) ==="
  if [[ -f "$PLANLIST" && $success_count -gt 0 ]]; then
    echo "Plan files created ($success_count total):"
    cat "$PLANLIST"
  else
    echo "No plan files created"
  fi
  # Exit with success if at least one app succeeded
  exit 0
fi