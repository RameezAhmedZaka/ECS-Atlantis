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
    [ -f "$dir/main.tf" ] && [ -f "$dir/variables.tf" ] && [ -f "$dir/providers.tf" ]
}

# Function to get environments for an app
get_environments() {
    local app_dir="$1"
    local envs=()
    declare -A env_map=( ["staging"]="stage" ["helia"]="helia" ["production"]="production" )

    for env in staging helia production; do
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

# Loop through all top-level directories (e.g., application, db, network, etc.)
for base_dir in */; do
    [ -d "$base_dir" ] || continue

    # Loop through each subdirectory (e.g., application/app1, db/mysql)
    for sub_dir in "$base_dir"*/; do
        [ -d "$sub_dir" ] || continue

        if is_terraform_project "$sub_dir"; then
            app_name="$(basename "$sub_dir")"
            envs=$(get_environments "$sub_dir")

            if [ -z "$envs" ]; then
                cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_dir%/}-${app_name}-default
    dir: $sub_dir
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
                project_names+=("${base_dir%/}-${app_name}-default")
            else
                prev_env=""
                for env in $envs; do
                    project_full_name="${base_dir%/}-${app_name}-${env}"

                    cat >> atlantis.yaml << PROJECT_EOF
  - name: $project_full_name
    dir: $sub_dir
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

                    # Add depends_on if there is a previous environment
                    if [ -n "$prev_env" ]; then
                        echo "    depends_on:" >> atlantis.yaml
                        echo "      - ${base_dir%/}-${app_name}-$prev_env" >> atlantis.yaml
                    fi

                    project_names+=("$project_full_name")
                    prev_env="$env"
                done
            fi
        fi
    done
done

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
            DESTROY_FLAG=""

            for arg in \${ATLANTIS_COMMENT_ARGS:-}; do
                arg_clean=\$(echo "\$arg" | xargs)
                case "\$arg_clean" in
                    -destroy|--destroy)
                        echo "❌ You cannot perform this action. Destroy is disabled and cannot be run."
                        exit 1
                        ;;
                    --)
                        ;;
                    *)
                        ;;
                esac
            done

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
            echo "Destroy flag: \$DESTROY_FLAG"

            cd "\$PROJECT_DIR"

            if [ -f "\$BACKEND_CONFIG" ]; then
              timeout 300 terraform init \
                -backend-config="\$BACKEND_CONFIG" \
                -input=false -reconfigure > /dev/null 2>&1
            else
              terraform init -input=false -reconfigure
            fi

            if [ -f "\$VAR_FILE" ]; then
              timeout 300 terraform plan \$DESTROY_FLAG \
                         -var-file="\$VAR_FILE" \
                         -out="\$PLANFILE"
            else
              terraform plan \$DESTROY_FLAG -out="\$PLANFILE"
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
