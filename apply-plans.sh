#!/bin/bash
set -euo pipefail

# Usage: ./apply-plans.sh <environment>
ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>"
  exit 2
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]]; then
  echo "No plan list found: $PLANLIST"
  exit 0
fi

if [[ ! -s "$PLANLIST" ]]; then
  echo "Plan list is empty: $PLANLIST"
  rm -f "$PLANLIST"
  exit 0
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

while IFS='|' read -r DIR PLAN; do
  if [[ -z "$DIR" || -z "$PLAN" ]]; then
    echo "Skipping malformed line in $PLANLIST"
    continue
  fi

  if [[ ! -f "$PLAN" ]]; then
    echo "Plan file not found: $PLAN (for dir $DIR), skipping."
    continue
  fi

  echo "=== Applying plan $PLAN for directory $DIR ==="
  if ! timeout 600 terraform -chdir="$DIR" apply -input=false -auto-approve "$PLAN"; then
    echo "Apply failed for $PLAN (dir $DIR). Leaving plan file for inspection: $PLAN"
    continue
  fi

  echo "Successfully applied $PLAN for $DIR"
  rm -f "$PLAN"
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="