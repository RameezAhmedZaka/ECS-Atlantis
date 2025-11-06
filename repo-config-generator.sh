# #!/bin/bash
# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: true
# parallel_apply: false
# projects:
# EOF

# # Check if a directory is a Terraform project
# is_terraform_project() {
#     local dir="$1"
#     [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
# }

# # Loop through top-level dirs (apps)
# for base_dir in */; do
#     [ -d "$base_dir" ] || continue
#     for app_dir in "$base_dir"*/; do
#         [ -d "$app_dir" ] || continue
#         if is_terraform_project "$app_dir"; then
#             app_name="$(basename "$app_dir")"

#             # Add project entries for each environment
#             for env in helia staging production; do
#                 env_path="${app_dir}env/${env}"
#                 [ -d "$env_path" ] || continue

#                 cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-${env}
#     dir: $env_path
#     autoplan:
#       enabled: true
#       when_modified:
#         - "../../*.tf"
#         - "../../config/*.tfvars"
#         - "../../env/*/*"
#     terraform_version: v1.6.6
#     workflow: ${env}_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#             done
#         fi
#     done
# done

# # Fixed workflows using only run steps (everything else unchanged)
# cat >> atlantis.yaml << 'EOF'
# workflows:
#   production_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/production/prod.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/production.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   staging_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl

#             terraform init -backend-config=env/staging/stage.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/stage.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   helia_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/helia/helia.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/helia.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE
# EOF

# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Compare changes against main branch
# git fetch origin main >/dev/null 2>&1 || true
# CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")

# # Function to check if any files in a directory changed
# has_changes() {
#     local dir="$1"
#     if [ -z "$CHANGED_FILES" ]; then
#         return 0  # If we can't detect changes, include all projects
#     fi
#     echo "$CHANGED_FILES" | grep -q "^$dir"
# }

# # Function to check if main Terraform files changed
# main_files_changed() {
#     if [ -z "$CHANGED_FILES" ]; then
#         return 1  # If we can't detect changes, assume main files didn't change
#     fi
#     echo "$CHANGED_FILES" | grep -q -E "(\.tf$|\.tfvars$)" | grep -v "/env/"
# }

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: false
# parallel_apply: false
# projects:
# EOF

# # Function to check if a directory is a Terraform project
# is_terraform_project() {
#     local dir="$1"
#     [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
# }

# # Loop through top-level dirs (apps)
# for base_dir in */; do
#     [ -d "$base_dir" ] || continue
#     for app_dir in "$base_dir"*/; do
#         [ -d "$app_dir" ] || continue
#         if is_terraform_project "$app_dir"; then
#             app_name="$(basename "$app_dir")"
            
#             # Check if main files changed (triggers all environments)
#             main_changed=$(main_files_changed && echo "true" || echo "false")
            
#             # Add project entries for each environment
#             for env in helia staging production; do
#                 env_path="${app_dir}env/${env}"
#                 [ -d "$env_path" ] || continue
                
#                 # Only include this environment if:
#                 # 1. Main files changed, OR
#                 # 2. This specific environment directory changed
#                 if [ "$main_changed" = "true" ] || has_changes "$env_path"; then
#                     cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-${env}
#     dir: $env_path
#     autoplan:
#       enabled: true
#       when_modified:
#         - "../../*.tf"
#         - "../../config/*.tfvars"
#         - "../../env/*/*"
#     terraform_version: v1.6.6
#     workflow: ${env}_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#                 else
#                     echo "Skipping ${base_dir%/}-${app_name}-${env} - no changes detected"
#                 fi
#             done
#         fi
#     done
# done

# # Fixed workflows using only run steps (everything else unchanged)
# cat >> atlantis.yaml << 'EOF'
# workflows:
#   production_workflow:
#     plan:
#       steps:
#         - run: |
#             terraform workspace select "prod-pr-$PULL_NUM" || terraform workspace new "prod-pr-$PULL_NUM"
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/production/prod.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/production.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   staging_workflow:
#     plan:
#       steps:
#         - run: |
#             terraform workspace select "stage-pr-$PULL_NUM" || terraform workspace new "stage-pr-$PULL_NUM"
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/staging/stage.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/stage.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   helia_workflow:
#     plan:
#       steps:
#         - run: |
#             terraform workspace select "helia-pr-$PULL_NUM" || terraform workspace new "helia-pr-$PULL_NUM"
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/helia/helia.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/helia.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE
# EOF

# set -euo pipefail

# echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# # Compare changes against main branch
# git fetch origin main >/dev/null 2>&1 || true
# CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")

# # Function to check if any files in a directory changed
# has_changes() {
#     local dir="$1"
#     if [ -z "$CHANGED_FILES" ]; then
#         return 0  # If we can't detect changes, include all projects
#     fi
#     echo "$CHANGED_FILES" | grep -q "^$dir"
# }

# # Function to check if main Terraform files changed
# main_files_changed() {
#     if [ -z "$CHANGED_FILES" ]; then
#         return 1  # If we can't detect changes, assume main files didn't change
#     fi
#     echo "$CHANGED_FILES" | grep -q -E "(\.tf$|\.tfvars$)" | grep -v "/env/"
# }

# # Start atlantis.yaml
# cat > atlantis.yaml <<-EOF
# ---
# version: 3
# automerge: true
# parallel_plan: false
# parallel_apply: false
# projects:
# EOF

# # Function to check if a directory is a Terraform project
# is_terraform_project() {
#     local dir="$1"
#     [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
# }

# # Loop through top-level dirs (apps)
# for base_dir in */; do
#     [ -d "$base_dir" ] || continue
#     for app_dir in "$base_dir"*/; do
#         [ -d "$app_dir" ] || continue
#         if is_terraform_project "$app_dir"; then
#             app_name="$(basename "$app_dir")"
            
#             # Check if main files changed (triggers all environments)
#             main_changed=$(main_files_changed && echo "true" || echo "false")
            
#             # Add project entries for each environment
#             for env in helia staging production; do
#                 env_path="${app_dir}env/${env}"
#                 [ -d "$env_path" ] || continue
                
#                 # Only include this environment if:
#                 # 1. Main files changed, OR
#                 # 2. This specific environment directory changed
#                 if [ "$main_changed" = "true" ] || has_changes "$env_path"; then
#                     cat >> atlantis.yaml << PROJECT_EOF
#   - name: ${base_dir%/}-${app_name}-${env}
#     dir: $env_path
#     autoplan:
#       enabled: true
#       when_modified:
#         - "../../*.tf"
#         - "../../config/*.tfvars"
#         - "../../env/*/*"
#     terraform_version: v1.6.6
#     workflow: ${env}_workflow
#     apply_requirements:
#       - approved
#       - mergeable
# PROJECT_EOF
#                 else
#                     echo "Skipping ${base_dir%/}-${app_name}-${env} - no changes detected"
#                 fi
#             done
#         fi
#     done
# done

# # Fixed workflows using only run steps (everything else unchanged)
# cat >> atlantis.yaml << 'EOF'
# workflows:
#   production_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/production/prod.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/production.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   staging_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/staging/stage.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/stage.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE

#   helia_workflow:
#     plan:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             rm -rf .terraform .terraform.lock.hcl
#             terraform init -backend-config=env/helia/helia.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
#             terraform plan -var-file=config/helia.tfvars -lock-timeout=10m -out=$PLANFILE
#     apply:
#       steps:
#         - run: |
#             echo "Project: $PROJECT_NAME"
#             cd "$(dirname "$PROJECT_DIR")/../.."
#             terraform apply -auto-approve $PLANFILE
# EOF

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
