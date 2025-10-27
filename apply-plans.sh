#!/usr/bin/env bash
set -euo pipefail
# repo-root-aware apply script — reads absolute directories from the plan list created by process-application.sh

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <env>"
  exit 1
fi

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

# Each line is: <absolute-directory>|<absolute-plan-path>
while IFS='|' read -r d PLAN || [[ -n "$d" ]]; do
  if [[ -z "$d" || -z "$PLAN" ]]; then
    echo "Invalid entry in plan list (missing dir or plan): '$d|$PLAN'"
    continue
  fi

  if [[ ! -d "$d" ]]; then
    echo "App directory not found: $d"
    continue
  fi

  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN for directory $d ==="
    if ! timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN"; then
      echo "Apply failed for $PLAN (directory $d)"
      continue
    fi
    echo "✅ Successfully applied $PLAN for $d"
    rm -f "$PLAN"
  else
    echo "Plan file not found: $PLAN (expected for $d)"
    ls -la "$PLAN" 2>/dev/null || ls -la /tmp/*.tfplan 2>/dev/null || echo "No plan files in /tmp/"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="