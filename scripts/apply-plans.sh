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
echo "Plan files to apply:"
cat "$PLANLIST"

# Count total plans to apply
total_plans=$(wc -l < "$PLANLIST" | tr -d ' ')
success_count=0
fail_count=0

while IFS='|' read -r d PLAN; do
  # Clean up any whitespace
  d=$(echo "$d" | xargs)
  PLAN=$(echo "$PLAN" | xargs)
  
  if [ -f "$PLAN" ]; then
    echo "=== Applying $PLAN for directory $d ==="
    
    if timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN"; then
      echo "✅ Successfully applied $PLAN"
      rm -f "$PLAN"
      success_count=$((success_count + 1))
    else
      echo "❌ Apply failed for $PLAN"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "❌ Plan file not found: $PLAN"
    echo "Current directory: $(pwd)"
    echo "Looking for plan files in /tmp/:"
    ls -la /tmp/*${ENV}*.tfplan 2>/dev/null || echo "No ${ENV} plan files in /tmp/"
    
    # Try to find the plan file by app name and environment
    APP_NAME=$(basename "$d")
    POSSIBLE_PLAN="/tmp/application_${APP_NAME}_${ENV}.tfplan"
    if [ -f "$POSSIBLE_PLAN" ]; then
      echo "🔍 Found plan file: $POSSIBLE_PLAN"
      echo "=== Applying $POSSIBLE_PLAN for directory $d ==="
      if timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$POSSIBLE_PLAN"; then
        echo "✅ Successfully applied $POSSIBLE_PLAN"
        rm -f "$POSSIBLE_PLAN"
        success_count=$((success_count + 1))
      else
        echo "❌ Apply failed for $POSSIBLE_PLAN"
        fail_count=$((fail_count + 1))
      fi
    else
      echo "No matching plan file found for $APP_NAME in $ENV"
      fail_count=$((fail_count + 1))
    fi
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="
echo "Summary: $success_count successful, $fail_count failed out of $total_plans total plans"

if [ $fail_count -gt 0 ]; then
  exit 1
fi