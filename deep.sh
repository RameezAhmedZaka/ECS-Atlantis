#!/bin/bash
# generate-atlantis-config.sh

# cat > atlantis.yaml << 'EOF'
# version: 3
# automerge: false
# parallel_plan: true
# parallel_apply: true

# projects:
# EOF

# Find all applications with S3 backend and generate project configs
grep -P 'backend[\s]+"s3"' applications/**/*.tf 2>/dev/null | rev | cut -d'/' -f2- | rev | sort | uniq | while read dir; do
    app_name=$(basename "$dir")
    
    # Production workspace
    cat >> atlantis.yaml << PROJECT
  - name: ${app_name}-production
    dir: ${dir}
    workspace: production
    autoplan:
      enabled: true
      when_modified: ["**/*.tf*", "**/*.tfvars", "env/production/*.conf"]
    terraform_version: v1.5.0
    workflow: standard-workflow
    apply_requirements: [mergeable]

PROJECT

    # Staging workspace
    cat >> atlantis.yaml << PROJECT
  - name: ${app_name}-staging
    dir: ${dir}
    workspace: staging
    autoplan:
      enabled: true
      when_modified: ["**/*.tf*", "**/*.tfvars", "env/staging/*.conf"]
    terraform_version: v1.5.0
    workflow: standard-workflow
    apply_requirements: [mergeable]

PROJECT
done

cat >> atlantis.yaml << 'EOF'

workflows:
  standard-workflow:
    plan:
      steps:
        - init:
            extra_args: 
              - -backend-config
              - ${app_name}/env/${ATLANTIS_WORKSPACE}/${ATLANTIS_WORKSPACE}.conf
        - plan:
            extra_args: 
              - -var-file
              - ${app_name}/config/${ATLANTIS_WORKSPACE}.tfvars
    apply:
      steps:
        - apply:
            extra_args: 
              - -var-file
              - config/${ATLANTIS_WORKSPACE}.tfvars
EOF

echo "Generated atlantis.yaml with dynamic projects!