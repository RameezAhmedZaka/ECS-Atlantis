#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="./atlantis_planfiles_${ENV}.lst"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -f "$PLANLIST" ]]; then
  echo ":x: No plan list found: $PLANLIST"
  echo "Available plan files in current directory:"
  find . -name "*.tfplan" -type f 2>/dev/null || echo "No plan files found"
  exit 1
fi

if [[ ! -s "$PLANLIST" ]]; then
  echo ":x: Plan list is empty: $PLANLIST"
  exit 1
fi

echo "Applying plans from: $PLANLIST"
cat "$PLANLIST"

while IFS= read -r PLAN; do
  if [[ -f "$PLAN" ]]; then
    echo "=== Applying $PLAN ==="
    
    # Extract directory from plan filename
    DIR_NAME=$(echo "$PLAN" | sed 's/^\.\///' | sed "s/_${ENV}\.tfplan//" | sed 's/_/\//g')
    
    if [[ -d "$DIR_NAME" ]]; then
      echo "Applying from directory: $DIR_NAME"
      terraform -chdir="$DIR_NAME" apply -input=false -auto-approve "$PLAN" || {
        echo ":x: Apply failed for $PLAN"
        continue
      }
    else
      echo ":x: Directory not found: $DIR_NAME"
      continue
    fi
    
    echo ":white_check_mark: Successfully applied $PLAN"
    rm -f "$PLAN"
  else
    echo ":warning: Plan file not found: $PLAN"
    echo "Current directory: $(pwd)"
    ls -la ./*.tfplan 2>/dev/null || echo "No plan files in current directory"
  fi
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "=== APPLY COMPLETED for $ENV at $(date) ==="