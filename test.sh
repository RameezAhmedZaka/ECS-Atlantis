#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

cat > atlantis.yaml <<EOF
---
version: 3
automerge: true
parallel_plan: true
parallel_apply: false
projects:
EOF

declare -A workflows_done

# Helper functions
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

get_first_four_chars() { echo "${1:0:4}" | tr '[:upper:]' '[:lower:]'; }
get_relative_path() { realpath --relative-to="." "$1"; }
get_environments() { local d="$1"; [ -d "$d/env" ] && find "$d/env" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort || echo ""; }
find_backend() { local p="$1" e="$2"; [ -d "$p/env/$e" ] || return; for f in "$p/env/$e"/*.conf; do [ -f "$f" ] && echo "$f" && return; done; }
find_tfvars() { local p="$1" e="$2"; [ -d "$p/config" ] || return; for f in "$p/config"/*.tfvars; do [ -f "$f" ] && echo "$f" && return; done; }
get_project_name() {
    local dir="$1"
    local parent=$(basename "$(dirname "$dir")")
    local base=$(basename "$dir")
    if [ "$parent" = "." ]; then
        echo "$base"
    else
        echo "${parent}-${base}"
    fi
}

# Find all projects
mapfile -t projects < <(find . -type f -name main.tf)

for main_tf in "${projects[@]}"; do
    project_dir=$(dirname "$main_tf")
    [ -d "$project_dir/env" ] || continue
    project_name=$(get_project_name "$project_dir")
    mapfile -t envs < <(get_environments "$project_dir")

    for env in "${envs[@]}"; do
        backend=$(get_relative_path "$(find_backend "$project_dir" "$env")")
        tfvars=$(get_relative_path "$(find_tfvars "$project_dir" "$env")")
        relative_dir=$(get_relative_path "$project_dir")

        [ -z "$backend" ] || [ -z "$tfvars" ] && continue

        # Add project block
        cat >> atlantis.yaml <<EOF
  - name: ${project_name}-${env}
    dir: $relative_dir
    autoplan:
      enabled: true
      when_modified:
        - "$relative_dir/*.tf"
        - "$relative_dir/config/*.tfvars"
        - "$relative_dir/env/*/*"
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
EOF

        # Record workflow to generate later
        workflows_done["$env"]="$backend|$tfvars"
    done
done

# Generate a single workflows: block
echo "workflows:" >> atlantis.yaml
for env in "${!workflows_done[@]}"; do
    IFS="|" read -r backend tfvars <<< "${workflows_done[$env]}"
    cat >> atlantis.yaml <<EOF
  ${env}_workflow:
    plan:
      steps:
        - run: |
            terraform init -backend-config="$backend" -reconfigure -lock=false -input=false
            terraform plan -var-file="$tfvars" -lock-timeout=10m -out=\$PLANFILE
    apply:
      steps:
        - run: |
            terraform apply -auto-approve \$PLANFILE
EOF
done

echo "Generated atlantis.yaml successfully"
