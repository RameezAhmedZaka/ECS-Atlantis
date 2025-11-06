#!/usr/bin/env bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Start the Atlantis YAML
cat > atlantis.yaml <<EOF
---
version: 3
automerge: true
parallel_plan: true
parallel_apply: false
projects:
EOF

# Arrays to track workflows
workflows_envs=()
workflows_backends=()
workflows_tfvars=()

# ----------------------
# Helper functions
# ----------------------

# Check if directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# First 4 chars, lowercase
get_first_four_chars() { echo "${1:0:4}" | tr '[:upper:]' '[:lower:]'; }

# Relative path from repo root
get_relative_path() { realpath --relative-to="." "$1"; }

# List environments inside a project
get_environments() {
    local d="$1"
    [ -d "$d/env" ] && find "$d/env" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort || echo ""
}

# Find backend config for env
find_backend() {
    local p="$1" e="$2"
    [ -d "$p/env/$e" ] || return
    for f in "$p/env/$e"/*.conf; do
        [ -f "$f" ] && echo "$f" && return
    done
}

# Find tfvars file for env
find_tfvars() {
    local p="$1" e="$2"
    [ -d "$p/config" ] || return
    for f in "$p/config"/*.tfvars; do
        [ -f "$f" ] && echo "$f" && return
    done
}

# Project name based on path
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

# ----------------------
# Find all Terraform projects
# ----------------------
mapfile -t projects < <(find . -type f -name main.tf)

for main_tf in "${projects[@]}"; do
    project_dir=$(dirname "$main_tf")
    [ -d "$project_dir/env" ] || continue
    project_name=$(get_project_name "$project_dir")
    mapfile -t envs < <(get_environments "$project_dir")

    for env in "${envs[@]}"; do
        backend=$(find_backend "$project_dir" "$env")
        tfvars=$(find_tfvars "$project_dir" "$env")
        relative_dir=$(get_relative_path "$project_dir")

        # Skip if either config is missing
        [ -z "$backend" ] || [ -z "$tfvars" ] && continue

        # Add project to Atlantis YAML
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

        # Track workflow for later
        workflows_envs+=("$env")
        workflows_backends+=("$backend")
        workflows_tfvars+=("$tfvars")
    done
done

# ----------------------
# Generate single workflows: block
# ----------------------
echo "workflows:" >> atlantis.yaml
for i in "${!workflows_envs[@]}"; do
    env="${workflows_envs[$i]}"
    backend="${workflows_backends[$i]}"
    tfvars="${workflows_tfvars[$i]}"

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
