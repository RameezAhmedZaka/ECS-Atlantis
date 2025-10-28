#!/bin/bash
set -euo pipefail
ENV="$1"
PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
APP_FILTER="${2:-}"

echo "=== STARTING APPLY for $ENV at $(date) ==="

if [[ ! -s "$PLANLIST" ]]; then
  echo "❌ Plan list missing or empty for $ENV: $PLANLIST"
  exit 0
fi

mapfile -t PLANFILES < "$PLANLIST"
APP_NAMES=()
for line in "${PLANFILES[@]}"; do
  d=$(echo "$line" | cut -d'|' -f1 | xargs)
  plan=$(echo "$line" | cut -d'|' -f2 | xargs)
  APP_NAMES+=("$(basename "$d")")
done

CUSTOM_OUTPUT_FILE="/tmp/atlantis_custom_output_${ENV}.md"
APP_COUNT=${#APP_NAMES[@]}

{
  echo "## 🚀 Atlantis Apply Summary for **$ENV**"
  echo ""
  echo "**Total Applications:** $APP_COUNT"
  echo ""
  echo "### 🧩 Applications Detected:"
  for app in "${APP_NAMES[@]}"; do
    echo "- **$app**"
  done
  echo ""
  echo "---"
  echo ""
  echo "### 🧱 Apply Commands"
  echo ""
  for app in "${APP_NAMES[@]}"; do
    echo '```bash'
    echo "atlantis apply -p apps-$ENV -- $app"
    echo '```'
  done
  echo ""
  echo "⏩ Apply all:"
  echo '```bash'
  echo "atlantis apply -p apps-$ENV"
  echo '```'
} > "$CUSTOM_OUTPUT_FILE"

# Apply each plan
while IFS='|' read -r d PLAN; do
  [[ -f "$PLAN" ]] || continue
  echo "=== Applying $PLAN for directory $d ==="
  timeout 600 terraform -chdir="$d" apply -auto-approve "$PLAN" || echo "❌ Failed for $PLAN"
  rm -f "$PLAN"
done < "$PLANLIST"

rm -f "$PLANLIST"
echo "✅ APPLY COMPLETE for $ENV"
