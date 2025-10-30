#!/bin/bash
set -euo pipefail

echo "version: 3" > atlantis.yaml
echo "automerge: true" >> atlantis.yaml
echo "parallel_plan: false" >> atlantis.yaml
echo "parallel_apply: false" >> atlantis.yaml
echo "projects:" >> atlantis.yaml

for dir in $(find . -type d -name "*.tf" -exec dirname {} \; | sort -u); do
  name=$(basename "$dir")
  cat >> atlantis.yaml <<EOF
  - name: $name
    dir: $dir
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "$dir/**"
    workflow: staging-workflow
    apply_requirements: []
EOF
done

echo "✅ Atlantis config generated."
