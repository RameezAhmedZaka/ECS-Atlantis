#!/bin/bash

cat > atlantis.yaml << 'EOF'
version: 3
automerge: false
parallel_plan: true
parallel_apply: true

projects:
EOF

# Find all apps and generate projects
for app_dir in application/*/; do
    if [[ -d "$app_dir" ]]; then
        app_name=$(basename "$app_dir")
        echo "Generating projects for: $app_name"
        
        # Staging project
        cat >> atlantis.yaml << EOF
  - name: ${app_name}-staging
    dir: .
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "application/${app_name}/main.tf"
        - "application/${app_name}/providers.tf"
        - "application/${app_name}/variables.tf"
        - "application/${app_name}/backend.tf"
        - "application/${app_name}/config/stage.tfvars"
        - "application/${app_name}/env/staging/**"
    workflow: staging-workflow

  - name: ${app_name}-production
    dir: .
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "application/${app_name}/main.tf"
        - "application/${app_name}/providers.tf"
        - "application/${app_name}/variables.tf"
        - "application/${app_name}/backend.tf"
        - "application/${app_name}/config/production.tfvars"
        - "application/${app_name}/env/production/**"
    workflow: production-workflow

EOF
    fi
done

cat >> atlantis.yaml << 'EOF'
workflows:
  staging-workflow:
    plan:
      steps:
        - init:
            extra_args: [-backend-config="application/${app_name}/env/staging/stage.conf", -reconfigure]
        - plan:
            extra_args: [-var-file="application/${app_name}/config/stage.tfvars", -out, "staging.tfplan"]
    apply:
      steps:
        - apply:
            extra_args: ["staging.tfplan"]

  production-workflow:
    plan:
      steps:
        - init:
            extra_args: [-backend-config="env/production/prod.conf", -reconfigure]
        - plan:
            extra_args: [-var-file="config/production.tfvars", -out, "production.tfplan"]
    apply:
      steps:
        - apply:
            extra_args: ["production.tfplan"]
EOF

echo "✅ Generated atlantis.yaml with all projects"