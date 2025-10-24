#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]]; then
  echo ":x: No plan list found: $PLANLIST"
  echo "Available plan files:"
  ls -la /tmp/*.tfplan 2>/dev/null || echo "No plan files found"
  exit 1
fi

if [[ ! -s "$PLANLIST" ]]; then
  echo ":x: Plan list is empty: $PLANLIST"
  exit 1
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

while IFS='|' read -r d PLAN; do
  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN for directory $d ==="
    
    # Change to the correct directory before applying
    if [[ -d "$d" ]]; then
      cd "$d" || {
        echo ":x: Cannot cd to $d"
        continue
      }
      terraform apply -input=false -auto-approve "$PLAN" || {
        echo ":x: Apply failed for $PLAN"
        cd - > /dev/null
        continue
      }
      cd - > /dev/null
    else
      echo ":x: Directory not found: $d"
      continue
    fi
    
    echo ":white_check_mark: Successfully applied $PLAN"
    rm -f "$PLAN"
  else
    echo ":warning: Plan file not found: $PLAN"
    echo "Looking for plan in: $(pwd)"
    ls -la "/tmp/" | grep "$(basename "$PLAN")" || echo "Plan file not found in /tmp/"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="