#!/bin/bash

APPS_DIR="./application"
OUTPUT_FILE="atla.yaml"

echo "version: 3" > $OUTPUT_FILE
echo "projects:" >> $OUTPUT_FILE

for app in "$APPS_DIR"/*; do
    if [ -d "$app" ]; then
        APP_NAME=$(basename "$app")

        # Development project
        echo "  - name: ${APP_NAME}-dev-deploy" >> $OUTPUT_FILE
        echo "    dir: applications/$APP_NAME" >> $OUTPUT_FILE
        echo "    workspace: development" >> $OUTPUT_FILE
        echo "    workflow: dev-workflow" >> $OUTPUT_FILE
        echo "    apply_requirements: []" >> $OUTPUT_FILE
        echo "    autoplan:" >> $OUTPUT_FILE
        echo "      when_modified: [\"*.tf\", \"config/*.tfvars\", \"modules/**/*.tf\", \"**/*.tf\"]" >> $OUTPUT_FILE
        echo "      enabled: true" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE

        # Production project
        echo "  - name: ${APP_NAME}-prod-deploy" >> $OUTPUT_FILE
        echo "    dir: applications/$APP_NAME" >> $OUTPUT_FILE
        echo "    workspace: production" >> $OUTPUT_FILE
        echo "    workflow: prod-workflow" >> $OUTPUT_FILE
        echo "    apply_requirements: []" >> $OUTPUT_FILE
        echo "    autoplan:" >> $OUTPUT_FILE
        echo "      when_modified: [\"*.tf\", \"config/*.tfvars\", \"modules/**/*.tf\", \"**/*.tf\"]" >> $OUTPUT_FILE
        echo "      enabled: true" >> $OUTPUT_FILE
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
        - init:
            extra_args: ["-backend-config=env/staging/stage.conf"]
        - plan: 
            extra_args: ["-var-file=config/stage.tfvars"]
    apply:
      steps:
        - apply:
            extra_args: ["-var-file=config/stage.tfvars"]

  prod-workflow:
    plan:
      steps:
        - run:
            command: ls
        - init:
            extra_args: ["-backend-config=env/production/prod.conf"]
        - plan: 
            extra_args: ["-var-file=./config/production.tfvars"]
    apply:
      steps:
        - apply:
            extra_args: ["-var-file=./config/production.tfvars"]
EOL

echo "Generated $OUTPUT_FILE with dev and prod workflows for all apps!"


