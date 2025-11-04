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

# Start new file
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Fetch latest main branch
git fetch origin main >/dev/null 2>&1 || true

# Get changed files compared to main
CHANGED_FILES=$(git diff --name-only origin/main...HEAD || echo "")

# Helper: check if directory has Terraform code
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] || [ -f "$dir/variables.tf" ] || [ -f "$dir/outputs.tf" ]
}

# Helper: check if main Terraform or config files changed
main_files_changed() {
    local app_dir="$1"
    echo "$CHANGED_FILES" | grep -qE "^${app_dir}/(main\.tf|variables\.tf|outputs\.tf|provider\.tf|.*\.tfvars|config/.*\.tfvars)$"
}

# Walk through all apps that have Terraform code
for app_dir in */; do
    [ -d "$app_dir" ] || continue
    is_terraform_project "$app_dir" || continue

    app_name=$(basename "$app_dir")

    # Find envs inside app_dir/env/
    if [ ! -d "$app_dir/env" ]; then
        echo "⚠️  Skipping $app_name — no env folder found."
        continue
    fi

    for env_path in "$app_dir"/env/*/; do
        [ -d "$env_path" ] || continue
        env=$(basename "$env_path")
        base_dir=$(basename "$(dirname "$app_dir")")

        # Determine if this env should be added
        env_changed=$(echo "$CHANGED_FILES" | grep -qE "^${app_dir}/env/${env}/" && echo "yes" || echo "no")
        main_changed=$(main_files_changed "$app_dir" && echo "yes" || echo "no")

        if [ "$env_changed" = "no" ] && [ "$main_changed" = "no" ]; then
            # Nothing changed relevant to this env — skip
            continue
        fi

        # Build dynamic when_modified list
        if [ "$main_changed" = "yes" ]; then
            # If shared files changed, trigger all envs
            WHEN_MODIFIED="
- ../../*.tf
- ../../config/*.tfvars
"
        else
            # If only env files changed
            WHEN_MODIFIED="
- ../../env/$env/*
"
        fi

        cat >> atlantis.yaml <<PROJECT_EOF
  - name: ${base_dir}-${app_name}-${env}
    dir: $env_path
    autoplan:
      enabled: true
      when_modified:$WHEN_MODIFIED
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
    done
done

# Fixed workflows
cat >> atlantis.yaml << 'EOF'
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
