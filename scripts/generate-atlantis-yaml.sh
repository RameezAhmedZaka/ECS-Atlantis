repos:
  - id: /.*/
    allow_custom_workflows: true
    allowed_overrides:
      - apply_requirements
      - workflow
      - plan_requirements
    apply_requirements: []
    workflow: multi_env_workflow
    pre_workflow_hooks:
      - run: |
          echo "Generating dynamic atlantis.yaml for $(basename $REPO_ROOT)"
          
          # Create dynamic atlantis.yaml
          cat > atlantis.yaml << EOF
version: 3
automerge: false
parallel_plan: true
parallel_apply: true
projects:
EOF

          # Function to check if directory is a valid Terraform project
          # Now requires ALL THREE essential files
          is_terraform_project() {
            local dir="$1"
            # Check for ALL THREE main Terraform files
            [ -f "$dir/main.tf" ] && [ -f "$dir/backend.tf" ] && [ -f "$dir/providers.tf" ]
          }

          # Function to discover environments from config directory
          discover_environments() {
            local dir="$1"
            local config_dir="$dir/config"
            
            if [ -d "$config_dir" ]; then
              # Find all .tfvars files and extract environment names
              find "$config_dir" -name "*.tfvars" -type f | \
              sed -E 's|.*/([^/]+)\.tfvars|\1|' | \
              sort -u
            else
              # If no config directory, return empty
              echo ""
            fi
          }

          # Find all directories and check if they're valid Terraform projects
          find . -type d -not -path "*/\.*" | while read dir; do
            if is_terraform_project "$dir"; then
              dir="${dir#./}"  # Remove leading ./
              
              # Discover available environments for this project
              environments=$(discover_environments "$dir")
              
              if [[ -n "$environments" ]]; then
                # Create a project for each environment
                for env in $environments; do
                  if [[ "$dir" =~ ^application/([^/]+)$ ]]; then
                    app_name="${BASH_REMATCH[1]}"
                    project_name="${app_name}-${env}"
                  else
                    folder_name=$(basename "$dir")
                    project_name="${folder_name}-${env}"
                  fi
                  
                  cat >> atlantis.yaml << EOF
  - name: $project_name
    dir: $dir
    autoplan:
      enabled: true
      when_modified: ["$dir/**/*", "$dir/config/$env.tfvars", "$dir/env/$env/*"]
    terraform_version: v1.5.0
    apply_requirements: [approved, mergeable]
EOF
                done
              else
                # If no environments found, create a default project
                if [[ "$dir" =~ ^application/([^/]+)$ ]]; then
                  project_name="app-${BASH_REMATCH[1]}"
                else
                  project_name=$(echo "$dir" | sed 's|/|-|g')
                fi
                
                cat >> atlantis.yaml << EOF
  - name: $project_name
    dir: $dir
    autoplan:
      enabled: true
      when_modified: ["$dir/**/*"]
    terraform_version: v1.5.0
    apply_requirements: [approved, mergeable]
EOF
              fi
            fi
          done

          cat >> atlantis.yaml << EOF