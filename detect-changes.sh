#!/bin/bash
set -euo pipefail
ENV="$1"

echo "🔍 Detecting changed applications for environment: $ENV"

# Find all changed files in this PR (Atlantis automatically checks out the branch)
CHANGED_FILES=$(git diff --name-only HEAD~1..HEAD || true)

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changed files detected."
  exit 0
fi

# Extract app directories under application/
mapfile -t changed_apps < <(echo "$CHANGED_FILES" | grep -E '^application/' | awk -F'/' '{print $2}' | sort -u)

if [[ ${#changed_apps[@]} -eq 0 ]]; then
  echo "No Terraform apps changed in application/ directory."
  exit 0
fi

echo "🧱 Changed applications (${#changed_apps[@]}): ${changed_apps[*]}"
echo
echo "💬 Suggested Atlantis commands:"
echo
for app in "${changed_apps[@]}"; do
  echo "👉 atlantis plan -p apps-${ENV} -- ${app}"
done

echo
echo "🚀 To apply all at once after approval:"
echo "👉 atlantis apply -p apps-${ENV}"
