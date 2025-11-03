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

            # Add project entries for each environment
            for env in helia staging production; do
                env_path="${app_dir}env/${env}"
                [ -d "$env_path" ] || continue

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
