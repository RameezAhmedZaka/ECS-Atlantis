#!/bin/bash
set -euo pipefail

# Find all application directories
mapfile -t apps < <(find application -maxdepth 1 -type d ! -name "application" | sed 's|application/||' | sort)

# Generate atlantis.yaml dynamically
cat > atlantis.generated.yaml << EOF
version: 3
automerge: false
parallel_plan: false
parallel_apply: false 

projects:
EOF

# Add projects for each app
for app in "${apps[@]}"; do
  cat >> atlantis.generated.yaml << EOF
  - name: application-${app}-staging
    dir: application/${app}
    workspace: staging
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "application/${app}/**"
    workflow: staging-workflow
    apply_requirements: []

  - name: application-${app}-production
    dir: application/${app}
    workspace: production
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "application/${app}/**"
    workflow: production-workflow
    apply_requirements: []

EOF
done

# Add workflows
cat >> atlantis.generated.yaml << EOF
workflows:
  staging-workflow:
    plan:
      steps:
        - run: |
            set -euo pipefail
            ENV="staging"
            APP_NAME=\$(echo "\$ATLANTIS_PROJECT_NAME" | sed 's/application-\\(.*\\)-staging/\\1/')
            echo "=== Processing \$APP_NAME STAGING environment ==="
            chmod +x ./process-application.sh
            ./process-application.sh "\$ENV" "\$APP_NAME"
    apply:
      steps:
        - run: |
            set -euo pipefail
            ENV="staging"
            echo "=== Applying STAGING environment ==="
            chmod +x ./apply-plans.sh
            ./apply-plans.sh "\$ENV"

  production-workflow:
    plan:
      steps:
        - run: |
            set -euo pipefail
            ENV="production"
            APP_NAME=\$(echo "\$ATLANTIS_PROJECT_NAME" | sed 's/application-\\(.*\\)-production/\\1/')
            echo "=== Processing \$APP_NAME PRODUCTION environment ==="
            chmod +x ./process-application.sh
            ./process-application.sh "\$ENV" "\$APP_NAME"
    apply:
      steps:
        - run: |
            set -euo pipefail
            ENV="production"
            echo "=== Applying PRODUCTION environment ==="
            chmod +x ./apply-plans.sh
            ./apply-plans.sh "\$ENV"
EOF

echo "Generated atlantis.generated.yaml with ${#apps[@]} application"