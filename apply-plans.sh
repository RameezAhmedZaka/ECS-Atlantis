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

# FIX: Use pipe separator to read both directory and plan path
while IFS='|' read -r d PLAN; do
  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN for directory $d ==="
    
    # FIX: Use -chdir to switch to the correct directory before apply
    timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN" || {
      echo "Apply failed for $PLAN"
      continue
    }
    echo "Successfully applied $PLAN"
    rm -f "$PLAN"
  else
    echo "Plan file not found: $PLAN"
    echo "Current directory: $(pwd)"
    echo "Looking in /tmp/:"
    ls -la /tmp/*.tfplan 2>/dev/null || echo "No plan files in /tmp/"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="