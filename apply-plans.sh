#!/bin/bash
set -euo pipefail

ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]] || [[ ! -s "$PLANLIST" ]]; then
  echo "No plan files to apply for $ENV"
  exit 1
fi

echo "Applying plans from: $PLANLIST"

while IFS='|' read -r d PLAN; do
  if [[ -f "$PLAN" ]]; then
    APP_NAME=$(basename "$d")
    echo "=== Applying $PLAN for $APP_NAME ==="
    timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN" || {
      echo "Apply failed for $APP_NAME"
      continue
    }
    echo ":white_check_mark: Successfully applied $APP_NAME"
    rm -f "$PLAN"
  else
    echo "Plan file not found: $PLAN"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="
