#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

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
            base_name="${base_dir%/}"

            # Create one project per app that handles all environments
            cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_name}-${app_name}
    dir: ${app_dir}
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/*/*"
    terraform_version: v1.6.6
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
        fi
    done
done

# Single workflow that detects environment based on changed files
cat >> atlantis.yaml << 'EOF'
workflows:
  default:
    plan:
      steps:
        - init:
            step_name: "Detect Environment and Initialize"
            run: |
              echo "Project: $PROJECT_NAME"
              echo "Working directory: $PWD"
              
              # Detect environment based on changed files
              ENVIRONMENT="production"  # default
              
              # Check which environment files were modified
              if [[ -n "$(echo "$CHANGED_FILES" | grep -E 'env/staging/|config/stage\.tfvars')" ]]; then
                ENVIRONMENT="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
              elif [[ -n "$(echo "$CHANGED_FILES" | grep -E 'env/helia/|config/helia\.tfvars')" ]]; then
                ENVIRONMENT="helia"
                BACKEND_CONFIG="env/helia/helia.conf"
                VAR_FILE="config/helia.tfvars"
              elif [[ -n "$(echo "$CHANGED_FILES" | grep -E 'env/production/|config/production\.tfvars')" ]]; then
                ENVIRONMENT="production"
                BACKEND_CONFIG="env/production/prod.conf"
                VAR_FILE="config/production.tfvars"
              else
                # If no specific env files changed, check all environments that might be affected
                # by common Terraform changes
                if [[ -n "$(echo "$CHANGED_FILES" | grep -E '\.tf$' | grep -v -E 'env/')" ]]; then
                  # Common TF files changed - plan for all environments
                  echo "Common Terraform files changed. Planning for all environments..."
                  ENVIRONMENT="all"
                else
                  # Default to production if we can't determine
                  BACKEND_CONFIG="env/production/prod.conf"
                  VAR_FILE="config/production.tfvars"
                fi
              fi
              
              echo "Detected environment: $ENVIRONMENT"
              
              # Store environment in file for apply phase
              echo "$ENVIRONMENT" > /tmp/current_environment.txt
              
              if [[ "$ENVIRONMENT" == "all" ]]; then
                # Plan for all environments
                for env in production staging helia; do
                  echo "=== Planning for $env environment ==="
                  BACKEND_CONFIG="env/$env/${env}.conf"
                  VAR_FILE="config/${env}.tfvars"
                  
                  # Handle naming variations
                  if [[ "$env" == "production" ]]; then
                    BACKEND_CONFIG="env/production/prod.conf"
                    VAR_FILE="config/production.tfvars"
                  elif [[ "$env" == "staging" ]]; then
                    BACKEND_CONFIG="env/staging/stage.conf"
                    VAR_FILE="config/stage.tfvars"
                  fi
                  
                  rm -rf .terraform .terraform.lock.hcl
                  terraform init -backend-config=$BACKEND_CONFIG -reconfigure -lock=false -input=false
                  terraform plan -var-file=$VAR_FILE -lock-timeout=10m -out=planfile.$env
                done
                echo "all" > /tmp/current_environment.txt
              else
                # Plan for specific environment
                rm -rf .terraform .terraform.lock.hcl
                terraform init -backend-config=$BACKEND_CONFIG -reconfigure -lock=false -input=false
                terraform plan -var-file=$VAR_FILE -lock-timeout=10m -out=$PLANFILE
                echo "$ENVIRONMENT" > /tmp/current_environment.txt
              fi
              
        - run:
            step_name: "Show Plan Summary"
            run: |
              ENVIRONMENT=$(cat /tmp/current_environment.txt)
              if [[ "$ENVIRONMENT" == "all" ]]; then
                for env in production staging helia; do
                  echo "=== Plan summary for $env ==="
                  terraform show -no-color planfile.$env | tail -20
                done
              else
                echo "=== Plan summary for $ENVIRONMENT ==="
                terraform show -no-color $PLANFILE | tail -20
              fi

    apply:
      steps:
        - run:
            step_name: "Apply Changes"
            run: |
              ENVIRONMENT=$(cat /tmp/current_environment.txt)
              echo "Applying changes for environment: $ENVIRONMENT"
              
              if [[ "$ENVIRONMENT" == "all" ]]; then
                # Apply for all environments
                for env in production staging helia; do
                  echo "=== Applying for $env environment ==="
                  if [[ -f "planfile.$env" ]]; then
                    terraform apply -auto-approve planfile.$env
                  else
                    echo "No plan file found for $env"
                  fi
                done
              else
                # Apply for specific environment
                if [[ -f "$PLANFILE" ]]; then
                  terraform apply -auto-approve $PLANFILE
                else
                  echo "No plan file found for $ENVIRONMENT"
                fi
              fi
EOF