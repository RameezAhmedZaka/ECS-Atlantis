# Generate projects and save into a temp file
grep -P 'backend[\s]+"s3"' **/*.tf |
  rev | cut -d'/' -f2- | rev |
  sort |
  uniq |
  while read d; do \
    echo '[ {"name": "'"$d"'","dir": "'"$d"'", "autoplan": {"when_modified": ["**/*.tf.*"] }} ]' | yq -PM; \
  done



# !/bin/bash

# APPS_DIR="application"
# OUTPUT_FILE="atlantis.yaml"

# # echo "version: 3" > $OUTPUT_FILE
# # echo "projects:" >> $OUTPUT_FILE

# for app in "$APPS_DIR"/*; do
#     if [ -d "$app" ]; then
#         APP_NAME=$(basename "$app")

#         # Development project
#         echo "  - name: ${APP_NAME}-dev-deploy" >> $OUTPUT_FILE
#         echo "    dir: application/$APP_NAME" >> $OUTPUT_FILE
#         echo "    workspace: development" >> $OUTPUT_FILE
#         echo "    workflow: dev-workflow" >> $OUTPUT_FILE
#         echo "    apply_requirements: []" >> $OUTPUT_FILE
#         echo "    autoplan:" >> $OUTPUT_FILE
#         echo "      when_modified: [\"*.tf\", \"config/*.tfvars\", \"modules/**/*.tf\", \"**/*.tf\"]" >> $OUTPUT_FILE
#         echo "      enabled: true" >> $OUTPUT_FILE
#         echo "    plan_extra_args:" >> $OUTPUT_FILE
#         echo "      - \"-backend-config=/$APP_NAME/env/staging/stage.conf\"" >> $OUTPUT_FILE
#         echo "      - \"-var-file=/$APP_NAME/config/stage.tfvars\"" >> $OUTPUT_FILE
#         echo "" >> $OUTPUT_FILE

#         # Production project
#         echo "  - name: ${APP_NAME}-prod-deploy" >> $OUTPUT_FILE
#         echo "    dir: application/$APP_NAME" >> $OUTPUT_FILE
#         echo "    workspace: production" >> $OUTPUT_FILE
#         echo "    workflow: prod-workflow" >> $OUTPUT_FILE
#         echo "    apply_requirements: []" >> $OUTPUT_FILE
#         echo "    autoplan:" >> $OUTPUT_FILE
#         echo "      when_modified: [\"*.tf\", \"config/*.tfvars\", \"modules/**/*.tf\", \"**/*.tf\"]" >> $OUTPUT_FILE
#         echo "      enabled: true" >> $OUTPUT_FILE
#         echo "    plan_extra_args:" >> $OUTPUT_FILE
#         echo "      - \"-backend-config=/$APP_NAME/env/production/prod.conf\"" >> $OUTPUT_FILE
#         echo "      - \"-var-file=/$APP_NAME/config/production.tfvars\"" >> $OUTPUT_FILE
#         echo "" >> $OUTPUT_FILE
#     fi
# done

# # Workflows section
# cat >> $OUTPUT_FILE <<EOL

# workflows:
#   dev-workflow:
#     plan:
#       steps:
#         - run:
#             command: ls
#         - init: {}
#         - plan: {}
#     apply:
#       steps:
#         - apply: {}

#   prod-workflow:
#     plan:
#       steps:
#         - run:
#             command: ls
#         - init: {}
#         - plan: {}
#     apply:
#       steps:
#         - apply: {}
# EOL