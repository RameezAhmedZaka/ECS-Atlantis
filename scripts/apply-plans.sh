#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
APP_FILTER="${2:-}"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [ ! -f "$PLANLIST" ]; then  # ✅ Changed to POSIX [ ]
  echo "No plan list found: $PLANLIST"
  echo "This usually means no changes were detected during planning."
  exit 0
fi

if [ ! -s "$PLANLIST" ]; then  # ✅ Changed to POSIX [ ]
  echo "Plan list is empty: $PLANLIST"
  echo "No changes to apply."
  exit 0
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

while IFS='|' read -r d PLAN; do
  # Clean up any whitespace
  d=$(echo "$d" | tr -d '[:space:]')
  PLAN=$(echo "$PLAN" | tr -d '[:space:]')
  
  if [ -f "$PLAN" ]; then  # ✅ Changed to POSIX [ ]
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
    APP_NAME=$(basename "$d")
    POSSIBLE_PLAN="/tmp/application_${APP_NAME}_${ENV}.tfplan"
    if [ -f "$POSSIBLE_PLAN" ]; then  # ✅ Changed to POSIX [ ]
      echo "🔍 Found plan file: $POSSIBLE_PLAN"
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

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="