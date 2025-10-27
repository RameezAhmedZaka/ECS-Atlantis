#!/usr/bin/env bash
set -euo pipefail

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

# Each line: <directory>|<absolute-plan-path>
while IFS='|' read -r d PLAN; do
  if [[ -z "$d" || -z "$PLAN" ]]; then
    echo "Invalid entry in plan list (missing dir or plan): '$d|$PLAN'"
    continue
  fi

  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN for directory $d ==="
    # Use -chdir to run terraform inside the app directory. Tell terraform the absolute plan file.
    if ! timeout 600 terraform -chdir="$d" apply -input=false -auto-approve "$PLAN"; then
      echo "Apply failed for $PLAN (directory $d)"
      continue
    fi
    echo ":white_check_mark: Successfully applied $PLAN for $d"
    rm -f "$PLAN"
  else
    echo "Plan file not found: $PLAN (expected for $d)"
    echo "Current directory: $(pwd)"
    echo "Listing /tmp matching pattern:"
    ls -la "/tmp/$(basename "$PLAN")" 2>/dev/null || ls -la /tmp/*.tfplan 2>/dev/null || echo "No plan files in /tmp/"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="