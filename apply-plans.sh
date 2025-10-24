#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]]; then
  echo "❌ No plan list found: $PLANLIST"
  exit 1
fi

if [[ ! -s "$PLANLIST" ]]; then
  echo "❌ Plan list is empty: $PLANLIST"
  exit 1
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

while IFS= read -r PLAN; do
  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN ==="
    timeout 600 terraform apply -input=false -auto-approve "$PLAN" || {
      echo "❌ Apply failed for $PLAN"
      continue
    }
    echo "✅ Successfully applied $PLAN"
    rm -f "$PLAN"
  else
    echo "⚠️ Plan file not found: $PLAN"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="