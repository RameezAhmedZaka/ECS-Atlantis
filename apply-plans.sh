#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"

if [[ -f "$PLANLIST" ]]; then
  while IFS= read -r PLAN; do
    if [[ -f "$PLAN" ]]; then
      terraform apply -input=false -auto-approve "$PLAN"
      rm -f "$PLAN"
    fi
  done < "$PLANLIST"
  rm -f "$PLANLIST"
fi