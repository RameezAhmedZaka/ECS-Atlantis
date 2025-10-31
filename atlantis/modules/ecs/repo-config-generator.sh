#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Create base atlantis.yaml
cat > atlantis.yaml << 'EOF'
version: 3
automerge: false
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
    for env in production staging helia; do
        if [ -f "$app_dir/config/$env.tfvars" ] && [ -d "$app_dir/env/$env" ]; then
            envs+=("$env")
        fi
    done
    echo "${envs[@]}"
}

# Loop through application apps
if [ -d "application" ]; then
    for app_dir in application/*; do
        [ -d "$app_dir" ] || continue
        if is_terraform_project "$app_dir"; then
            app_name=$(basename "$app_dir")
            envs=$(get_environments "$app_dir")

            if [ -z "$envs" ]; then
                # Default project if no env detected
                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${app_name}-default
    dir: $app_dir
    autoplan:
      enabled: true
      when_modified:
        - "$app_dir/**/*"
    terraform_version: v1.5.0
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
            else
                # Create project for each environment
                for env in $envs; do
                    cat >> atlantis.yaml << PROJECT_EOF
  - name: ${app_name}-${env}
    dir: $app_dir
    autoplan:
      enabled: true
      when_modified:
        - "$app_dir/**/*"
        - "$app_dir/config/$env.tfvars"
        - "$app_dir/env/$env/*"
    terraform_version: v1.5.0
    apply_requirements:
      - approved
      - mergeable
PROJECT_EOF
                done
            fi
        fi
    done
fi

# Workflows
cat >> atlantis.yaml << 'EOF'
workflows:
  multi_env_workflow:
    plan:
      steps:
        - run: |
            case "$PROJECT_NAME" in
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

            echo "Planning for environment: $ENV"
            echo "Using backend config: $BACKEND_CONFIG"
            echo "Using var file: $VAR_FILE"

            if [ -f "$BACKEND_CONFIG" ]; then
              terraform init -chdir="$d" -backend-config="$BACKEND_CONFIG" -input=false -reconfigure
            else
              Not found
            fi

            if [ -f "$VAR_FILE" ]; then
              terraform plan -var-file="$VAR_FILE" -out="$PLANFILE"
            else
              terraform plan -out="$PLANFILE"
            fi
    apply:
      steps:
        - run: |
            case "$PROJECT_NAME" in
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

            echo "Applying for environment: $ENV"
            if [ -f "$BACKEND_CONFIG" ]; then
              terraform init -backend-config="$BACKEND_CONFIG" -input=false -reconfigure
            fi

            if [ -f "$VAR_FILE" ]; then
              terraform apply -var-file="$VAR_FILE" "$PLANFILE"
            else
              terraform apply "$PLANFILE"
            fi
EOF

echo "Generated atlantis.yaml successfully!"
