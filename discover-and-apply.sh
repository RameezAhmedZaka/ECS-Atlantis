#!/bin/bash
set -euo pipefail

echo "=== DYNAMIC DISCOVERY AND APPLY ==="

# Find all plan files and apply them
find application -name "*.tfplan" -type f | while read -r plan_file; do
    app_dir=$(dirname "$plan_file")
    plan_name=$(basename "$plan_file")
    
    echo ""
    echo "=== APPLYING: $app_dir ($plan_name) ==="
    
    terraform -chdir="$app_dir" apply -input=false -auto-approve "$plan_name"
    
    # Clean up plan file
    rm -f "$plan_file"
    echo "✅ Applied: $app_dir/$plan_name"
done

echo ""
echo "=== APPLY COMPLETE ==="