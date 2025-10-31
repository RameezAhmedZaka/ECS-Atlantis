#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Create base atlantis.yaml with document start
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Function to check if directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    [ -f "$dir/main.tf" ] && [ -f "$dir/backend.tf" ] && [ -f "$dir/providers.tf" ]
}

# Function to get environments for an app
get_environments() {
    local app_dir="$1"
    local envs=()
    declare -A env_map=( ["production"]="production" ["staging"]="stage" ["helia"]="helia" )

    for env in "${!env_map[@]}"; do
        tfvars_file="$app_dir/config/${env_map[$env]}.tfvars"
        env_dir="$app_dir/env/$env"
        if [ -f "$tfvars_file" ] && [ -d "$env_dir" ]; then
            envs+=("$env")
        fi
    done
    echo "${envs[@]}"
}

# Array to track project names
declare -a project_names=()

# Loop through application apps
if [ -d "application" ]; then
    for app_dir in application/*; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name=$(basename "$app_dir")
            envs=$(get_environments "$app_dir")

            if [ -z "$envs" ]; then
                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${app_name}-default
    dir: $app_dir
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/*/*"
    terraform_version: v1.6.6
    workflow: multi_env_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                project_names+=("${app_name}-default")
            else
                for env in $envs; do
                    cat >> atlantis.yaml << PROJECT_EOF
  - name: ${app_name}-${env}
    dir: $app_dir
    autoplan:
      enabled: true
      when_modified:
        - "*.tf"
        - "config/*.tfvars"
        - "env/$env/*"
    terraform_version: v1.6.6
    workflow: multi_env_workflow
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                    project_names+=("${app_name}-${env}")
                done
            fi
        fi
    done
fi

echo "Total projects configured: ${#project_names[@]}"
echo "Project names: ${project_names[*]}"

# Workflows section
cat >> atlantis.yaml <<-EOF
workflows:
  multi_env_workflow:
    plan:
      steps:
        - run: |
            PLANFILE="plan.tfplan"
            if echo "${ATLANTIS_COMMENT_BODY:-}" | grep -iq "destroy"; then
            echo "Destroy commands are not allowed through Atlantis!"
            exit 1
            fi


            case "\$PROJECT_NAME" in
              *-production)
                ENV="production"
                BACKEND_CONFIG="env/production/prod.conf"
                VAR_FILE="config/production.tfvars"
                ;;
              *-staging)
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
              *-helia)
                ENV="helia"
                BACKEND_CONFIG="env/helia/helia.conf"
                VAR_FILE="config/helia.tfvars"
                ;;
              *)
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
            esac

            echo "Planning for environment: \$ENV"
            echo "Using backend config: \$BACKEND_CONFIG"
            echo "Using var file: \$VAR_FILE"

            cd "\$PROJECT_DIR"

            if [ -f "\$BACKEND_CONFIG" ]; then
              timeout 300 terraform init \
                -backend-config="\$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure
            fi

            if [ -f "\$VAR_FILE" ]; then
              timeout 300 terraform plan \
                         -var-file="\$VAR_FILE" \
                         -out="\$PLANFILE"
            else
              terraform plan -out="\$PLANFILE"
            fi

    apply:
      steps:
        - run: |
            PLANFILE="plan.tfplan"

            case "\$PROJECT_NAME" in
              *-production)
                ENV="production"
                BACKEND_CONFIG="env/production/prod.conf"
                VAR_FILE="config/production.tfvars"
                ;;
              *-staging)
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
              *-helia)
                ENV="helia"
                BACKEND_CONFIG="env/helia/helia.conf"
                VAR_FILE="config/helia.tfvars"
                ;;
              *)
                ENV="staging"
                BACKEND_CONFIG="env/staging/stage.conf"
                VAR_FILE="config/stage.tfvars"
                ;;
            esac

            echo "Applying for environment: \$ENV"

            cd "\$PROJECT_DIR"

            if [ -f "\$BACKEND_CONFIG" ]; then
              timeout 300 terraform init \
                -backend-config="\$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure > /dev/null 2>&1
            fi

            # Apply the plan if it exists, otherwise do a raw apply with var-file
            if [ -f "\$PLANFILE" ]; then
              timeout 600 terraform apply -input=false -auto-approve "\$PLANFILE" || {
                echo "Apply failed for \$PLANFILE"
              }
            else
              timeout 600 terraform apply -var-file="\$VAR_FILE" -input=false -auto-approve || {
                echo "Apply failed for \$PROJECT_DIR"
              }
            fi
EOF