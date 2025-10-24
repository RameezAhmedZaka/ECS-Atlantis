APPS_DIR="./application"
OUTPUT_FILE="atlanti.yaml"
# echo "version: 3" > $OUTPUT_FILE
# echo "projects:" >> $OUTPUT_FILE

for app in "$APPS_DIR"/*; do
    if [ -d "$app" ]; then
        APP_NAME=$(basename "$app")

        # Development project
        echo "  - name: ${APP_NAME}-dev-deploy" >> $OUTPUT_FILE
        echo "    dir: application/$APP_NAME" >> $OUTPUT_FILE
        echo "    workspace: development" >> $OUTPUT_FILE
        echo "    workflow: dev-workflow" >> $OUTPUT_FILE
        echo "    apply_requiremversion: 3
automerge: true
parallel_plan: true
parallel_apply: true

projects:
# Dynamically generated projects
# Each app will have two workspaces: production and staging
# backend-config and var-file are set per workspace

{{- $apps := (exec "bash" "-c" "grep -Pl 'backend[\\s]+\"s3\"' applications/*/*.tf | rev | cut -d'/' -f2- | rev | sort | uniq") }}
{{- range $apps.Split "\n" }}
  - name: {{ . }}-production
    dir: {{ . }}
    workspace: production
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "**/*.tf"
        - "config/production.tfvars"
    workflow: default
    apply_requirements: []
    workspace_hooks:
      init:
        steps:
          - run: terraform init -backend-config={{ . }}/env/production/prod.conf
      plan:
        steps:
          - run: terraform plan -var-file={{ . }}/config/production.tfvars
      apply:
        steps:
          - run: terraform apply -var-file={{ . }}/config/production.tfvars

  - name: {{ . }}-staging
    dir: {{ . }}
    workspace: staging
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "**/*.tf"
        - "config/stage.tfvars"
    workflow: default
    apply_requirements: []
    workspace_hooks:
      init:
        steps:
          - run: terraform init -backend-config={{ . }}/env/staging/stage.conf
      plan:
        steps:
          - run: terraform plan -var-file={{ . }}/config/stage.tfvars
      apply:
        steps:
          - run: terraform apply -var-file={{ . }}/config/stage.tfvars

{{- end }}
ents: []" >> $OUTPUT_FILE
        echo "    autoplan:" >> $OUTPUT_FILE
        echo "      when_modified: [\"*.tf\", \"config/*.tfvars\", \"modules/**/*.tf\", \"**/*.tf\"]" >> $OUTPUT_FILE
        echo "      enabled: true" >> $OUTPUT_FILE
        echo "    plan_extra_args:" >> $OUTPUT_FILE
        echo "      - \"-backend-config=/$APP_NAME/env/staging/stage.conf\"" >> $OUTPUT_FILE
        echo "      - \"-var-file=/$APP_NAME/config/stage.tfvars\"" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE

        # Production project
        echo "  - name: ${APP_NAME}-prod-deploy" >> $OUTPUT_FILE
        echo "    dir: application/$APP_NAME" >> $OUTPUT_FILE
        echo "    workspace: production" >> $OUTPUT_FILE
        echo "    workflow: prod-workflow" >> $OUTPUT_FILE
        echo "    apply_requirements: []" >> $OUTPUT_FILE
        echo "    autoplan:" >> $OUTPUT_FILE
        echo "      when_modified: [\"*.tf\", \"config/*.tfvars\", \"modules/**/*.tf\", \"**/*.tf\"]" >> $OUTPUT_FILE
        echo "      enabled: true" >> $OUTPUT_FILE
        echo "    plan_extra_args:" >> $OUTPUT_FILE
        echo "      - \"-backend-config=/$APP_NAME/env/production/prod.conf\"" >> $OUTPUT_FILE
        echo "      - \"-var-file=/$APP_NAME/config/production.tfvars\"" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE
    fi
done

# Workflows section
cat >> $OUTPUT_FILE <<EOL

workflows:
  dev-workflow:
    plan:
      steps:
        - run:
            command: ls
        - init: {}
        - plan: {}
    apply:
      steps:
        - apply: {}

  prod-workflow:
    plan:
      steps:
        - run:
            command: ls
        - init: {}
        - plan: {}
    apply:
      steps:
        - apply: {}
EOL

