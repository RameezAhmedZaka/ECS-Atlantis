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

#!/bin/bash
set -euo pipefail

echo "🔧 Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Always compare current branch changes against main
git fetch origin main >/dev/null 2>&1 || true
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")

# Function: check if a directory is a Terraform project (old logic)
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Function: detect if main Terraform files changed (not inside /env/)
main_files_changed() {
    if [ -z "$CHANGED_FILES" ]; then
        return 1
    fi
    echo "$CHANGED_FILES" | grep -Eq "^[^/]+/.+\.(tf|tfvars)$" && ! echo "$CHANGED_FILES" | grep -q "/env/"
}

# Function: detect if a specific environment directory changed
env_changed() {
    local env_path="$1"
    echo "$CHANGED_FILES" | grep -Eq "^${env_path%/}/"
}

# Start writing atlantis.yaml
cat > atlantis.yaml <<EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Loop through top-level directories (apps)
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name="$(basename "$app_dir")"

            # Check if main Terraform files changed (triggers all envs)
            if main_files_changed; then
                trigger_all_envs=true
            else
                trigger_all_envs=false
            fi

            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue

                if [ "$trigger_all_envs" = true ] || env_changed "$env_path"; then
                    echo "✅ Including ${base_dir%/}-${app_name}-${env}"

                    # Set when_modified patterns dynamically
                    if [ "$trigger_all_envs" = true ]; then
                        when_modified="- ../../*.tf\n        - ../../config/*.tfvars\n        - ../../env/*/*"
                    else
                        when_modified="- ../../env/${env}/*"
                    fi

                    cat >> atlantis.yaml <<PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: $env_path
    autoplan:
      enabled: true
      when_modified:
        $when_modified
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                else
                    echo "⏭️  Skipping ${base_dir%/}-${app_name}-${env} (no relevant changes)"
                fi
            done
        fi
    done
done

# Add workflows (unchanged)
cat >> atlantis.yaml <<'EOF'

workflows:
  production_workflow:
    plan:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            cd "$(dirname "$PROJECT_DIR")/../.."
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config=env/production/prod.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
            terraform plan -var-file=config/production.tfvars -lock-timeout=10m -out=$PLANFILE
    apply:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            cd "$(dirname "$PROJECT_DIR")/../.."
            terraform apply -auto-approve $PLANFILE

  staging_workflow:
    plan:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            cd "$(dirname "$PROJECT_DIR")/../.."
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config=env/staging/stage.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
            terraform plan -var-file=config/stage.tfvars -lock-timeout=10m -out=$PLANFILE
    apply:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            cd "$(dirname "$PROJECT_DIR")/../.."
            terraform apply -auto-approve $PLANFILE

  helia_workflow:
    plan:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            cd "$(dirname "$PROJECT_DIR")/../.."
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config=env/helia/helia.conf -reconfigure -lock=false -input=false > /dev/null 2>&1
            terraform plan -var-file=config/helia.tfvars -lock-timeout=10m -out=$PLANFILE
    apply:
      steps:
        - run: |
            echo "Project: $PROJECT_NAME"
            cd "$(dirname "$PROJECT_DIR")/../.."
            terraform apply -auto-approve $PLANFILE
EOF

