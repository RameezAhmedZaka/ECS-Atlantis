#!/bin/bash
set -euo pipefail
ENV="$1"
RAW_FILTER="${2:-}"

echo "=== INITIALIZING TERRAFORM for $ENV at $(date) ==="

# Parse arguments for filter only (destroy is disabled)
APP_FILTER=""

# Use POSIX-compliant way to split by comma
OLD_IFS="$IFS"
IFS=','
set -- $RAW_FILTER
IFS="$OLD_IFS"

for arg; do
    arg_clean=$(echo "$arg" | xargs)
    case "$arg_clean" in
        -destroy|--destroy)
            echo "❌ You cannot perform this action. Destroy is disabled and cannot be run."
            exit 1
            ;;
        --)
            ;;
        *)
            if [ -n "$arg_clean" ]; then
                APP_FILTER="$arg_clean"
            fi
            ;;
    esac
done

echo "App filter: $APP_FILTER"

# Find application directories using POSIX-compliant method
dirs=$(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [ -z "$dirs" ]; then
  echo "No applications found!"
  exit 1
fi

echo "Found applications:"
echo "$dirs"

# Create init status file
INIT_STATUS_FILE="/tmp/atlantis_init_status_${ENV}.lst"
: > "$INIT_STATUS_FILE"

init_count=0

# Initialize each directory using while-read loop (POSIX-compliant)
echo "$dirs" | while IFS= read -r d; do
  if [ -f "$d/main.tf" ]; then
    APP_NAME=$(basename "$d")

    if [ -n "$APP_FILTER" ] && [ "$APP_NAME" != "$APP_FILTER" ]; then
      echo "=== Skipping $APP_NAME initialization (does not match filter: $APP_FILTER) ==="
      continue
    fi

    echo "=== Initializing $APP_NAME ($ENV) ==="
    
    # Determine backend config and var file based on environment
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
    
    echo "Directory: $d"
    echo "Backend config: $BACKEND_CONFIG"
    echo "Var file: $VAR_FILE"
    
    # Check if files exist
    if [ ! -f "$d/$BACKEND_CONFIG" ]; then
      echo "❌ Backend config not found: $d/$BACKEND_CONFIG"
      echo "$APP_NAME|FAILED|Backend config missing: $BACKEND_CONFIG" >> "$INIT_STATUS_FILE"
      continue
    fi
    
    if [ ! -f "$d/$VAR_FILE" ]; then
      echo "❌ Var file not found: $d/$VAR_FILE"
      echo "$APP_NAME|FAILED|Var file missing: $VAR_FILE" >> "$INIT_STATUS_FILE"
      continue
    fi
    
    # Clean up existing .terraform directory
    rm -rf "$d/.terraform"
    
    # Initialize with backend config
    echo "Step 1: Initializing Terraform..."
    if timeout 120 terraform -chdir="$d" init -upgrade \
      -backend-config="$BACKEND_CONFIG" \
      -reconfigure \
      -input=false; then
      
      echo "✅ Successfully initialized $APP_NAME"
      echo "$APP_NAME|SUCCESS" >> "$INIT_STATUS_FILE"
      init_count=$((init_count + 1))
    else
      echo "❌ Init failed for $APP_NAME"
      echo "$APP_NAME|FAILED|Terraform init command failed" >> "$INIT_STATUS_FILE"
    fi
    
  else
    echo "Skipping $d (main.tf missing)"
  fi
done

# Summary
echo "=== INITIALIZATION COMPLETED for $ENV at $(date) ==="
echo "Successfully initialized $init_count application(s)"

if [ -n "$APP_FILTER" ] && [ "$init_count" -eq 0 ]; then
  echo "⚠️  No applications matched filter: $APP_FILTER"
  echo "Available applications:"
  echo "$dirs" | while IFS= read -r d; do
    if [ -f "$d/main.tf" ]; then
      echo "  - $(basename "$d")"
    fi
  done
fi

# Display init status
echo "Initialization Status:"
cat "$INIT_STATUS_FILE" | while IFS='|' read -r app status message; do
  if [ "$status" = "SUCCESS" ]; then
    echo "  ✅ $app: Success"
  else
    echo "  ❌ $app: Failed - ${message:-Unknown error}"
  fi
done