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

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Get the current branch and determine the base branch for comparison
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH="main"  # or "master", "develop" - adjust as needed

# If we're already on main branch, compare with previous commit
# Otherwise, compare with main branch
if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
    COMPARE_REF="HEAD~1"
else
    COMPARE_REF="$BASE_BRANCH"
fi

# Get the changed files compared to base branch
CHANGED_FILES=$(git diff --name-only "$COMPARE_REF"...HEAD 2>/dev/null || echo "")

echo "Comparing against: $COMPARE_REF"
echo "Changed files:"
echo "$CHANGED_FILES"

# Function to check if any files in a directory changed
has_changes() {
    local dir="$1"
    if [ -z "$CHANGED_FILES" ]; then
        return 0  # If we can't detect changes, include all projects
    fi
    echo "$CHANGED_FILES" | grep -q "^$dir"
}

# Function to check if main Terraform files changed
main_files_changed() {
    if [ -z "$CHANGED_FILES" ]; then
        return 1  # If we can't detect changes, assume main files didn't change
    fi
    echo "$CHANGED_FILES" | grep -q -E "(\.tf$|\.tfvars$)" | grep -v "/env/"
}

# Start atlantis.yaml
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Check if a directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Loop through top-level dirs (apps)
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name="$(basename "$app_dir")"
            
            # Check if main files changed (triggers all environments)
            main_changed=$(main_files_changed && echo "true" || echo "false")
            
            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue
                
                # Only include this environment if:
                # 1. Main files changed, OR
                # 2. This specific environment directory changed
                if [ "$main_changed" = "true" ] || has_changes "$env_path"; then
                    cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: $env_path
    autoplan:
      enabled: true
      when_modified:
        - "../../*.tf"
        - "../../config/*.tfvars"
        - "../../env/*/*"
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                    echo "Including ${base_dir%/}-${app_name}-${env} - changes detected"
                else
                    echo "Skipping ${base_dir%/}-${app_name}-${env} - no changes detected"
                fi
            done
        fi
    done
done

# Fixed workflows using only run steps (everything else unchanged)
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