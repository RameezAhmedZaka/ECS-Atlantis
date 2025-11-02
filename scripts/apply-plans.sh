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

# Check if the plan list was created with a specific filter by looking at changed apps list
CHANGED_APPS_LIST="/tmp/atlantis_changed_apps_${ENV}.lst"
PLANNED_FILTER=""
if [ -f "$CHANGED_APPS_LIST" ] && [ -n "$APP_FILTER" ]; then
    # If APP_FILTER is provided during apply, use it to filter
    PLANNED_FILTER="$APP_FILTER"
    echo "Using apply-time filter: $PLANNED_FILTER"
elif [ -f "$CHANGED_APPS_LIST" ] && [ -s "$CHANGED_APPS_LIST" ]; then
    # If no filter provided but changed apps list exists, check if it contains multiple apps
    # If it contains only one app, that means the plan was created with a filter
    APP_COUNT=$(wc -l < "$CHANGED_APPS_LIST" | tr -d ' ')
    if [ "$APP_COUNT" -eq 1 ]; then
        PLANNED_FILTER=$(head -1 "$CHANGED_APPS_LIST")
        echo "Detected single application plan from planning phase: $PLANNED_FILTER"
    fi
fi

while IFS='|' read -r d PLAN; do
  # Clean up any whitespace
  d=$(echo "$d" | tr -d '[:space:]')
  PLAN=$(echo "$PLAN" | tr -d '[:space:]')
  
  # Extract app name from directory
  APP_NAME=$(basename "$d")
  
  # Apply filter logic: use apply-time filter if provided, otherwise use detected planned filter
  CURRENT_FILTER="${APP_FILTER:-$PLANNED_FILTER}"
  
  if [ -n "$CURRENT_FILTER" ] && [ "$APP_NAME" != "$CURRENT_FILTER" ]; then
    echo "Skipping $APP_NAME because it doesn't match filter: $CURRENT_FILTER"
    continue
  fi

  

  if [ -f "$PLAN" ]; then  
    echo "=== Applying $PLAN for directory $d ==="
    
    timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN" || {
      echo "Apply failed for $PLAN"
      continue
    }
    echo "✅ Successfully applied $PLAN"
    rm -f "$PLAN"
  else
    echo "Plan file not found: $PLAN"
    echo "Current directory: $(pwd)"
    echo "Looking for plan files in /tmp/:"
    ls -la /tmp/*${ENV}*.tfplan 2>/dev/null || echo "No ${ENV} plan files in /tmp/"
    
    # Try to find the plan file by app name and environment
    POSSIBLE_PLAN="/tmp/application_${APP_NAME}_${ENV}.tfplan"
    if [ -f "$POSSIBLE_PLAN" ]; then  
      echo "🔍 Found plan file: $POSSIBLE_PLAN"
      
      # Check filter for possible plan as well
      if [ -n "$CURRENT_FILTER" ] && [ "$APP_NAME" != "$CURRENT_FILTER" ]; then
        echo "Skipping $POSSIBLE_PLAN because $APP_NAME doesn't match filter: $CURRENT_FILTER"
        continue
      fi
      
      echo "=== Applying $POSSIBLE_PLAN for directory $d ==="
      timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$POSSIBLE_PLAN" && {
        echo "✅ Successfully applied $POSSIBLE_PLAN"
        rm -f "$POSSIBLE_PLAN"
      } || {
        echo "❌ Apply failed for $POSSIBLE_PLAN"
      }
    else
      echo "No matching plan file found for $APP_NAME in $ENV"
    fi
  fi
done < "$PLANLIST"

# Only remove the plan list if we're not using a specific filter
if [ -z "$APP_FILTER" ] && [ -z "$PLANNED_FILTER" ]; then
  rm -f "$PLANLIST"
  rm -f "$CHANGED_APPS_LIST"
else
  echo "Preserving plan files for filtered apply"
fi
