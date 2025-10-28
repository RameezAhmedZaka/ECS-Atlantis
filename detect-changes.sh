#!/bin/bash
set -euo pipefail

# Script to generate Atlantis commands based on changed applications
CHANGED_APPS=$(git diff --name-only HEAD~1 HEAD | grep -o 'application/[^/]*' | sort -u | sed 's|application/||')

if [[ -z "$CHANGED_APPS" ]]; then
    echo "No application changes detected."
    exit 0
fi

echo "Changed applications: $CHANGED_APPS"
echo ""
echo "=== ATLANTIS COMMANDS ==="
echo ""

# Generate individual plan commands for each environment
for app in $CHANGED_APPS; do
    echo "# Plan commands for $app:"
    echo "atlantis plan -p apps-staging -- $app"
    echo "atlantis plan -p apps-production -- $app"
    echo "atlantis plan -p apps-helia -- $app"
    echo ""
done

# Generate bulk apply commands
echo "# Apply all plans for each environment:"
echo "atlantis apply -p apps-staging"
echo "atlantis apply -p apps-production" 
echo "atlantis apply -p apps-helia"
echo ""

# Generate individual apply commands (optional)
echo "# Individual apply commands:"
for app in $CHANGED_APPS; do
    echo "# Apply commands for $app:"
    echo "atlantis apply -p apps-staging -- $app"
    echo "atlantis apply -p apps-production -- $app"
    echo "atlantis apply -p apps-helia -- $app"
    echo ""
done