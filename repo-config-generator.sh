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

echo "=== Debugging Atlantis Config Generation ==="
echo "Working directory: $(pwd)"
echo "Basename: $(basename "$(pwd)")"

# Get the current branch and determine the base branch for comparison
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
BASE_BRANCH="main"  # Change to "master" if needed

echo "Current branch: $CURRENT_BRANCH"
echo "Base branch: $BASE_BRANCH"

# Check if we're on main or feature branch
if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
    # On main branch - compare with previous commit
    COMPARE_REF="HEAD~1"
    echo "On main branch, comparing with: $COMPARE_REF"
else
    # On feature branch - compare with main
    COMPARE_REF="$BASE_BRANCH"
    echo "On feature branch, comparing with: $COMPARE_REF"
fi

# Verify the compare ref exists
if ! git rev-parse --verify "$COMPARE_REF" >/dev/null 2>&1; then
    echo "WARNING: Comparison reference '$COMPARE_REF' not found. Using fallback."
    COMPARE_REF="HEAD~1"
    if ! git rev-parse --verify "$COMPARE_REF" >/dev/null 2>&1; then
        echo "WARNING: HEAD~1 also not found. Will include all projects."
        CHANGED_FILES=""
    else
        CHANGED_FILES=$(git diff --name-only "$COMPARE_REF" HEAD 2>/dev/null || echo "")
    fi
else
    CHANGED_FILES=$(git diff --name-only "$COMPARE_REF" HEAD 2>/dev/null || echo "")
fi

echo "=== CHANGED FILES ==="
echo "$CHANGED_FILES"
echo "====================="

# Function to check if any files in a directory changed
has_changes() {
    local dir="$1"
    if [ -z "$CHANGED_FILES" ]; then
        echo "DEBUG: No changed files detected, including all projects"
        return 0  # If we can't detect changes, include all projects
    fi
    if echo "$CHANGED_FILES" | grep -q "^$dir"; then
        echo "DEBUG: Changes detected in directory: $dir"
        return 0
    else
        echo "DEBUG: No changes detected in directory: $dir"
        return 1
    fi
}

# Function to check if main Terraform files changed
main_files_changed() {
    if [ -z "$CHANGED_FILES" ]; then
        echo "DEBUG: No changed files list, assuming main files didn't change"
        return 1
    fi
    if echo "$CHANGED_FILES" | grep -q -E "(\.tf$|\.tfvars$)"; then
        echo "DEBUG: Main Terraform files changed"
        return 0
    else
        echo "DEBUG: No main Terraform files changed"
        return 1
    fi
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
    if [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]; then
        echo "DEBUG: Found Terraform project: $dir"
        return 0
    else
        echo "DEBUG: Not a Terraform project (missing required files): $dir"
        return 1
    fi
}

# Debug directory structure
echo "=== DIRECTORY STRUCTURE ==="
find . -maxdepth 3 -type d -name "env" | head -20
echo "==========================="

# Counter for projects
PROJECT_COUNT=0

# Loop through top-level dirs (apps)
for base_dir in */; do
    [ -d "$base_dir" ] || continue
    echo "Checking base directory: $base_dir"
    
    for app_dir in "$base_dir"*/; do
        [ -d "$app_dir" ] || continue
        echo "Checking app directory: $app_dir"
        
        if is_terraform_project "$app_dir"; then
            app_name="$(basename "$app_dir")"
            echo "Processing Terraform project: $app_name"
            
            # Check if main files changed (triggers all environments)
            if main_files_changed; then
                main_changed="true"
                echo "MAIN FILES CHANGED - including all environments for $app_name"
            else
                main_changed="false"
            fi
            
            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                echo "Checking environment path: $env_path"
                
                if [ -d "$env_path" ]; then
                    echo "Found environment directory: $env_path"
                    
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
                        echo "✓ INCLUDED: ${base_dir%/}-${app_name}-${env}"
                        PROJECT_COUNT=$((PROJECT_COUNT + 1))
                    else
                        echo "✗ SKIPPED: ${base_dir%/}-${app_name}-${env} - no changes detected"
                    fi
                else
                    echo "Environment directory not found: $env_path"
                fi
            done
        fi
    done
done

echo "Total projects included: $PROJECT_COUNT"

# If no projects were included, add a dummy project to avoid empty config
if [ "$PROJECT_COUNT" -eq 0 ]; then
    echo "WARNING: No projects included. Adding comment to avoid empty file."
    cat >> atlantis.yaml << EOF
  # No projects with changes detected
  - name: no-changes-detected
    dir: /
    autoplan:
      enabled: false
    terraform_version: v1.6.6
    workflow: production_workflow
    apply_requirements: []
EOF
fi

# Fixed workflows using only run steps
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
