#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(pwd)"

# Start atlantis.yaml
cat > atlantis.yaml <<-EOF
---
version: 3
automerge: false
parallel_plan: false
parallel_apply: false
projects:
EOF

# Find all Terraform projects by looking for main.tf files
find . -name "main.tf" -type f | while read -r main_tf; do
    project_dir=$(dirname "$main_tf")
    
    # Check if this is an environment-specific directory (env/*)
    if [[ "$project_dir" =~ /env/(production|staging|helia)$ ]]; then
        env=$(echo "$project_dir" | grep -oE "(production|staging|helia)$")
        app_dir=$(dirname "$(dirname "$project_dir")")
        app_name=$(basename "$app_dir")
        base_dir=$(dirname "$app_dir")
        base_name=$(basename "$base_dir")
        
        echo "Found project: $base_name/$app_name ($env) in $project_dir"
        
        # Set environment-specific patterns
        case $env in
            "production")
                when_modified=(
                  "*.tf"
                  "../*.tf"
                  "../../*.tf"
                  "../../config/production.tfvars"
                  "*.conf"
                  "../config/production.tfvars"
                )
                ;;
            "staging")
                when_modified=(
                  "*.tf"
                  "../*.tf"
                  "../../*.tf"
                  "../../config/stage.tfvars"
                  "*.conf"
                  "../config/stage.tfvars"
                )
                ;;
            "helia")
                when_modified=(
                  "*.tf"
                  "../*.tf"
                  "../../*.tf"
                  "../../config/helia.tfvars"
                  "*.conf"
                  "../config/helia.tfvars"
                )
                ;;
        esac

        cat >> atlantis.yaml << PROJECT_EOF
  - name: ${base_name}-${app_name}-${env}
    dir: ${project_dir}
    autoplan:
      enabled: true
      when_modified:
$(printf "        - \"%s\"\n" "${when_modified[@]}")
    terraform_version: v1.6.6
    apply_requirements:
      - approved
PROJECT_EOF
    fi
done

# Add workflows
cat >> atlantis.yaml << 'EOF'
workflows:
  default:
    plan:
      steps:
        - run: |
            echo "Planning for project: $PROJECT_NAME"
            echo "Working directory: $(pwd)"
            
            # Determine environment and config based on project name
            if [[ "$PROJECT_NAME" == *-production ]]; then
              echo "Environment: Production"
              BACKEND_CONFIG="prod.conf"
              VAR_FILE="../../config/production.tfvars"
            elif [[ "$PROJECT_NAME" == *-staging ]]; then
              echo "Environment: Staging"
              BACKEND_CONFIG="stage.conf"
              VAR_FILE="../../config/stage.tfvars"
            elif [[ "$PROJECT_NAME" == *-helia ]]; then
              echo "Environment: Helia"
              BACKEND_CONFIG="helia.conf"
              VAR_FILE="../../config/helia.tfvars"
            else
              echo "Unknown environment, using defaults"
              BACKEND_CONFIG="prod.conf"
              VAR_FILE="../../config/production.tfvars"
            fi
            
            echo "Backend config: $BACKEND_CONFIG"
            echo "Var file: $VAR_FILE"
            
            # Clean up and initialize
            rm -rf .terraform .terraform.lock.hcl
            terraform init -backend-config="$BACKEND_CONFIG" -reconfigure -input=false
            terraform plan -var-file="$VAR_FILE" -lock-timeout=10m -out=planfile

        - run: |
            echo "--- Plan Summary ---"
            terraform show -no-color planfile | tail -n 20

    apply:
      steps:
        - run: |
            echo "Applying for project: $PROJECT_NAME"
            echo "Working directory: $(pwd)"
            
            # Determine environment and config based on project name
            if [[ "$PROJECT_NAME" == *-production ]]; then
              echo "Environment: Production"
              BACKEND_CONFIG="prod.conf"
              VAR_FILE="../../config/production.tfvars"
            elif [[ "$PROJECT_NAME" == *-staging ]]; then
              echo "Environment: Staging"
              BACKEND_CONFIG="stage.conf"
              VAR_FILE="../../config/stage.tfvars"
            elif [[ "$PROJECT_NAME" == *-helia ]]; then
              echo "Environment: Helia"
              BACKEND_CONFIG="helia.conf"
              VAR_FILE="../../config/helia.tfvars"
            else
              echo "Unknown environment, using defaults"
              BACKEND_CONFIG="prod.conf"
              VAR_FILE="../../config/production.tfvars"
            fi
            
            echo "Backend config: $BACKEND_CONFIG"
            echo "Var file: $VAR_FILE"
            
            # Initialize and apply
            terraform init -backend-config="$BACKEND_CONFIG" -reconfigure -input=false
            terraform apply -auto-approve planfile
EOF

echo "Generated atlantis.yaml with the following projects:"
