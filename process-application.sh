#!/bin/bash
set -euo pipefail

ENV="$1"
RAW_FILTER="${2:-}"

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

# Validate environment
case "$ENV" in
    "production"|"staging"|"helia")
        # Valid environment
        ;;
    *)
        echo "❌ ERROR: Invalid environment '$ENV'. Must be one of: production, staging, helia"
        exit 1
        ;;
esac

# Find application directories
mapfile -t dirs < <(find application -type f -name "main.tf" | sed 's|/main.tf||' | sort -u)
if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "❌ No applications found!"
    exit 1
fi

echo "Found ${#dirs[@]} applications"

# Show available apps if filter is provided but no apps match
if [[ -n "$APP_FILTER" ]]; then
    echo "Filtering for app: $APP_FILTER"
    
    # Check if any apps match the filter
    matching_apps=()
    for d in "${dirs[@]}"; do
        APP_NAME=$(basename "$d")
        if [[ "$APP_NAME" == "$APP_FILTER" ]]; then
            matching_apps+=("$d")
        fi
    done
    
    if [[ ${#matching_apps[@]} -eq 0 ]]; then
        echo "❌ No applications matched filter: $APP_FILTER"
        echo "Available applications:"
        for d in "${dirs[@]}"; do
            if [[ -f "$d/main.tf" ]]; then
                echo "  - $(basename "$d")"
            fi
        done
        exit 1
    fi
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
processed_count=0
failed_count=0

for d in "${dirs[@]}"; do
    if [[ ! -f "$d/main.tf" ]]; then
        echo "⚠️  Skipping $d (main.tf missing)"
        continue
    fi

    APP_NAME=$(basename "$d")

    # Apply filter if specified
    if [[ -n "$APP_FILTER" && "$APP_NAME" != "$APP_FILTER" ]]; then
        continue
    fi

    echo ""
    echo "=== PROCESSING $APP_NAME ($ENV) ==="
    
    # Set environment-specific files
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
    
    echo "📁 Directory: $d"
    echo "⚙️  Backend config: $BACKEND_CONFIG"
    echo "📄 Var file: $VAR_FILE"
    
    # Check if required files exist
    if [[ ! -f "$d/$BACKEND_CONFIG" ]]; then
        echo "❌ Backend config not found: $d/$BACKEND_CONFIG"
        ((failed_count++))
        continue
    fi
    if [[ ! -f "$d/$VAR_FILE" ]]; then
        echo "❌ Var file not found: $d/$VAR_FILE"
        ((failed_count++))
        continue
    fi
    
    # Clean up and initialize
    echo "🔄 Step 1: Cleaning previous state..."
    rm -rf "$d/.terraform" || true
    
    echo "🚀 Step 2: Initializing Terraform..."
    if ! timeout 120 terraform -chdir="$d" init -upgrade \
        -backend-config="$BACKEND_CONFIG" \
        -reconfigure \
        -input=false; then
        echo "❌ Init failed for $APP_NAME"
        ((failed_count++))
        continue
    fi

    # Create unique plan file name
    PLAN_NAME="application_${APP_NAME}_${ENV}.tfplan"
    PLAN="/tmp/${PLAN_NAME}"
    
    # Add destroy flag if needed
    DESTROY_ARG=""
    DESTROY_MODE=""
    if [[ "$DESTROY_FLAG" == "true" ]]; then
        DESTROY_ARG="-destroy"
        DESTROY_MODE="🗑️  DESTROY MODE - "
        echo "⚠️  DESTROY MODE ENABLED - This will destroy resources!"
    fi
    
    echo "📋 Step 3: ${DESTROY_MODE}Generating plan..."
    echo "📄 Plan output: $PLAN"
    
    # Plan with var-file and optional destroy flag
    if ! timeout 300 terraform -chdir="$d" plan \
        -input=false \
        -lock-timeout=5m \
        -var-file="$VAR_FILE" \
        $DESTROY_ARG \
        -out="$PLAN"; then
        echo "❌ Plan failed for $APP_NAME"
        ((failed_count++))
        continue
    fi

    echo "$d|$PLAN" >> "$PLANLIST"
    echo "✅ Successfully planned $APP_NAME"
    ((processed_count++))
done

echo ""
echo "=== SUMMARY ==="
echo "✅ Successfully processed: $processed_count application(s)"
if [[ $failed_count -gt 0 ]]; then
    echo "❌ Failed: $failed_count application(s)"
fi

if [[ $processed_count -gt 0 ]]; then
    echo ""
    echo "📋 Plan files created:"
    cat "$PLANLIST"
    
    echo ""
    echo "💡 To apply all plans:"
    echo "   atlantis apply -p $ENV"
    
    if [[ -n "$APP_FILTER" ]]; then
        echo ""
        echo "💡 To apply specific app:"
        echo "   atlantis apply -p $ENV -- $APP_FILTER"
    fi
else
    echo "❌ No plans were successfully created"
    if [[ -n "$APP_FILTER" ]]; then
        echo "   Filter: $APP_FILTER"
    fi
fi

echo "=== COMPLETED $ENV at $(date) ==="