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

while IFS='|' read -r APP_DIR PLAN; do
  if [[ -f "$APP_DIR/$PLAN" ]]; then
    APP_NAME=$(basename "$APP_DIR")
    echo "=== Applying $PLAN for $APP_NAME ==="
    
    timeout 600 terraform -chdir="$APP_DIR" apply -input=false -auto-approve "$PLAN" || {
      echo "Apply failed for $PLAN"
      continue
    }
    echo ":white_check_mark: Successfully applied $PLAN for $APP_NAME"
    rm -f "$APP_DIR/$PLAN"
  else
    echo "Plan file not found: $APP_DIR/$PLAN"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="