---
repos:
  - id: /.*/
    allow_custom_workflows: true
    allowed_overrides:
      - apply_requirements
      - workflow
      - plan_requirements
    apply_requirements: []
    workflow: default
    pre_workflow_hooks:
      - run: |
          echo "Generating dynamic atlantis.yaml for $(basename $REPO_ROOT)"

          cat > atlantis.yaml <<'INIT_EOF'
version: 3
automerge: false
parallel_plan: true
parallel_apply: true

projects:
INIT_EOF

          is_terraform_project() {
            local dir="$1"
            [ -f "$dir/main.tf" ] && [ -f "$dir/backend.tf" ] && [ -f "$dir/providers.tf" ]
          }

          discover_environments() {
            local dir="$1"
            local config_dir="$dir/config"
            if [ -d "$config_dir" ]; then
              find "$config_dir" -name "*.tfvars" -type f | sed -E 's|.*/([^/]+)\.tfvars|\1|' | sort -u
            else
              echo ""
            fi
          }

          find . -type d -not -path "*/\.*" | while read dir; do
            if is_terraform_project "$dir"; then
              dir="${dir#./}"
              environments=$(discover_environments "$dir")

              if [[ -n "$environments" ]]; then
                for env in $environments; do
                  if [[ "$dir" =~ ^application/([^/]+)$ ]]; then
                    app_name="${BASH_REMATCH[1]}"
                    project_name="${app_name}-${env}"
                  else
                    folder_name=$(basename "$dir")
                    project_name="${folder_name}-${env}"
                  fi

                  # Use printf to avoid heredoc indentation issues
                  printf '  - name: %s\n    dir: %s\n    autoplan:\n      enabled: true\n      when_modified:\n        - "%s/**/*"\n        - "%s/config/%s.tfvars"\n        - "%s/env/%s/*"\n    terraform_version: v1.5.0\n    apply_requirements:\n      - approved\n      - mergeable\n' \
                    "$project_name" "$dir" "$dir" "$dir" "$env" "$dir" "$env" >> atlantis.yaml
                done
              else
                if [[ "$dir" =~ ^application/([^/]+)$ ]]; then
                  project_name="app-${BASH_REMATCH[1]}"
                else
                  project_name=$(echo "$dir" | sed 's|/|-|g')
                fi

                # Use printf for default projects too
                printf '  - name: %s\n    dir: %s\n    autoplan:\n      enabled: true\n      when_modified:\n        - "%s/**/*"\n    terraform_version: v1.5.0\n    apply_requirements:\n      - approved\n      - mergeable\n' \
                  "$project_name" "$dir" "$dir" >> atlantis.yaml
              fi
            fi
          done

          # Add the workflow section
          cat >> atlantis.yaml <<'WORKFLOW_EOF'

workflows:
  default:
    plan:
      steps:
        - init
        - plan
    apply:
      steps:
        - apply
WORKFLOW_EOF

          echo "Generated atlantis.yaml with dynamic projects"
        description: "Generate dynamic atlantis configuration"