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

set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Compare changes against main branch
# Fetch main and suppress output
git fetch origin main >/dev/null 2>&1 || true
# Get list of changed files relative to main branch
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")

# Function to check if any files in a directory changed
has_changes() {
    local dir="$1"
    # If CHANGED_FILES is empty, we default to including all projects (return 0)
    # The project inclusion logic later handles this based on the 'main_changed' flag.
    # Here, we only check for specific directory changes.
    if [ -z "$CHANGED_FILES" ]; then
        return 1 # Assume no specific directory changes if no changes are detected at all
    fi
    echo "$CHANGED_FILES" | grep -q "^$dir"
}

# Function to check if main Terraform files changed (excluding env/)
main_files_changed() {
    # If no changes were detected, return 1 (false) for main files
    if [ -z "$CHANGED_FILES" ]; then
        return 1
    fi
    
    # Check for .tf or .tfvars files NOT in a directory containing "/env/"
    # This is more robust than trying to pipe grep -v
    echo "$CHANGED_FILES" | grep -E "(\.tf$|\.tfvars$)" | grep -v "/env/" | grep -q "."
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

# Function to check if a directory is a Terraform project
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
            
            # Check if main files changed (triggers all environments for this app)
            # Use a variable to store the result of the function call
            main_changed="false"
            if main_files_changed; then
                main_changed="true"
            fi
            
            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue
                
                # Check for specific environment changes
                env_changed="false"
                if has_changes "$env_path"; then
                    env_changed="true"
                fi
                
                # Only include this environment if:
                # 1. Main files changed, OR
                # 2. This specific environment directory changed
                if [ "$main_changed" = "true" ] || [ "$env_changed" = "true" ]; then
                    cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-${env}
    dir: $env_path
    autoplan:
      enabled: true
      # Autoplan on changes to main app files or the specific env directory
      when_modified:
        - "../../*.tf"
        - "../../config/*.tfvars"
        - "**.tf"
        - "**.tfvars"
    terraform_version: v1.6.6
    workflow: ${env}_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                else
                    echo "Skipping ${base_dir%/}-${app_name}-${env} - no changes detected"
                fi
            done
        fi
    done
done

# Fixed workflows using only run steps (everything else unchanged)
# Note: The 'cd' command in the workflows assumes the project structure:
# <base_dir>/<app_dir>/env/<env>/
# The project 'dir' is the innermost folder: $PROJECT_DIR = <base_dir>/<app_dir>/env/<env>/
# cd "$(dirname "$PROJECT_DIR")/../.." goes up 3 levels:
# 1. to <base_dir>/<app_dir>/env/
# 2. to <base_dir>/<app_dir>/
# 3. to <base_dir>/ (This seems incorrect for accessing config/ and env/ from <base_dir>/<app_dir>/)
# Assuming the intention is to run 'terraform init/plan/apply' from the <base_dir>/<app_dir>/ directory,
# you should only go up two levels: cd "$(dirname "$PROJECT_DIR")/.."
# I will keep your original 'cd' command as I don't know your exact repository structure,
# but please verify the pathing in your 'run' steps.

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