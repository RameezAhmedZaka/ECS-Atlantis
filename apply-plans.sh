#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <staging|production|helia|all>
Reads /tmp/atlantis_planfiles_<ENV>.lst and applies each plan.
EOF
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY (ENV=$ENV) at $(date) ==="

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
  if [[ -z "$d" || -z "$PLAN" ]]; then
    echo "Malformed entry in plan list: '$d|$PLAN' -- skipping"
    continue
  fi

  if [[ ! -f "$PLAN" ]]; then
    echo "Plan file not found: $PLAN"
    echo "Current directory: $(pwd)"
    echo "Listing /tmp for matching tfplan files:"
    ls -la /tmp/*"${PLAN##*/}"* 2>/dev/null || echo "No matching plan files in /tmp/"
    continue
  fi

  echo "=== Applying $PLAN for directory $d ==="
  if ! timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN"; then
    echo "Apply failed for $PLAN -- continuing with next plan"
    continue
  fi

  echo "✅ Successfully applied $PLAN"
  rm -f "$PLAN"
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED (ENV=$ENV) at $(date) ==="