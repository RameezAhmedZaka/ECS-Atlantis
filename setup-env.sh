
# # Generate projects and save into a temp file
cd application || exit 1
for app in */ ; do
  APP_NAME="${app%/}"
  echo "[{\"name\": \"${APP_NAME}-dev-deploy\", \"dir\": \"application/${APP_NAME}\", \"workspace\": \"staging\", \"autoplan\": {\"when_modified\": [\"**/*.tf.*\"]}, \"plan_extra_args\": [\"-backend-config=application/${APP_NAME}/env/staging/stage.conf\", \"-var-file=application/${APP_NAME}/config/stage.tfvars\"]}]"
  echo "[{\"name\": \"${APP_NAME}-prod-deploy\", \"dir\": \"application/${APP_NAME}\", \"workspace\": \"production\", \"autoplan\": {\"when_modified\": [\"**/*.tf.*\"]}, \"plan_extra_args\": [\"-backend-config=application/${APP_NAME}/env/production/prod.conf\", \"-var-file=application/${APP_NAME}/config/production.tfvars\"]}]"

done | yq -PM
