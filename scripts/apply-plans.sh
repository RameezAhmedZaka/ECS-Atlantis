#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
APP_FILTER="${2:-}"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [ ! -f "$PLANLIST" ]; then
  echo "No plan list found: $PLANLIST"
  echo "This usually means no changes were detected during planning."
  exit 0
fi

if [ ! -s "$PLANLIST" ]; then
  echo "Plan list is empty: $PLANLIST"
  echo "No changes to apply."
  exit 0
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

APPLIED_COUNT=0
FAILED_COUNT=0

while IFS='|' read -r d PLAN; do
  # Clean up any whitespace
  d=$(echo "$d" | tr -d '[:space:]')
  PLAN=$(echo "$PLAN" | tr -d '[:space:]')
  
  if [ -f "$PLAN" ]; then
    APP_NAME=$(basename "$d")
    
    # Apply filter if specified
    if [ -n "$APP_FILTER" ] && [ "$APP_NAME" != "$APP_FILTER" ]; then
      echo "=== Skipping $APP_NAME (does not match filter: $APP_FILTER) ==="
      continue
    fi
    
    echo "=== Applying $PLAN for $APP_NAME ==="
    
    if timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN"; then
      echo "✅ Successfully applied $APP_NAME"
      rm -f "$PLAN"
      APPLIED_COUNT=$((APPLIED_COUNT + 1))
    else
      echo "❌ Apply failed for $APP_NAME"
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
  else
    echo "Plan file not found: $PLAN"
    
    # Try to find the plan file by app name and environment
    APP_NAME=$(basename "$d")
    POSSIBLE_PLAN="/tmp/application_${APP_NAME}_${ENV}.tfplan"
    if [ -f "$POSSIBLE_PLAN" ]; then
      echo "🔍 Found plan file: $POSSIBLE_PLAN"
      echo "=== Applying $POSSIBLE_PLAN for $APP_NAME ==="
      
      if timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$POSSIBLE_PLAN"; then
        echo "✅ Successfully applied $APP_NAME"
        rm -f "$POSSIBLE_PLAN"
        APPLIED_COUNT=$((APPLIED_COUNT + 1))
      else
        echo "❌ Apply failed for $APP_NAME"
        FAILED_COUNT=$((FAILED_COUNT + 1))
      fi
    else
      echo "No matching plan file found for $APP_NAME in $ENV"
    fi
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"

echo "=== APPLY COMPLETED for $ENV at $(date) ==="
echo "Summary: $APPLIED_COUNT applications applied successfully, $FAILED_COUNT failed"