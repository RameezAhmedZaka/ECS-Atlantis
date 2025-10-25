#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]]; then
  echo "No plan list found: $PLANLIST"
  exit 1
fi

if [[ ! -s "$PLANLIST" ]]; then
  echo "Plan list is empty: $PLANLIST"
  exit 1
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

while IFS='|' read -r d PLAN; do
  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN for directory $d ==="
    
    # Check if this is a destroy plan
    if [[ "$PLAN" == *"_destroy.tfplan" ]]; then
        echo "This is a DESTROY plan - will remove resources"
    fi
    
    timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN" || {
      echo "Apply failed for $PLAN"
      continue
    }
    
    if [[ "$PLAN" == *"_destroy.tfplan" ]]; then
        echo ":wastebasket: Successfully destroyed resources with $PLAN"
    else
        echo ":white_check_mark: Successfully applied $PLAN"
    fi
    
    rm -f "$PLAN"
  else
    echo "Plan file not found: $PLAN"
    echo "Current directory: $(pwd)"
    echo "Looking for plan files:"
    ls -la ./*.tfplan 2>/dev/null || echo "No plan files in current directory"
    ls -la /tmp/*.tfplan 2>/dev/null || echo "No plan files in /tmp/"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="