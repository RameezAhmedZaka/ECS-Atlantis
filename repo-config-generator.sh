#!/bin/bash
set -euo pipefail

echo "Generating dynamic atlantis.yaml for $(basename "$(pwd)")"

# Start atlantis.yaml
cat > atlantis.yaml <<EOF
---
version: 3
automerge: true
parallel_plan: false
parallel_apply: false
projects:
EOF

# Check if a directory is a Terraform project
is_terraform_project() {
    local dir="$1"
    if [ ! -d "$dir/env" ]; then return 1; fi
    if [ ! -f "$dir/main.tf" ]; then return 1; fi
    if [ -z "$(find "$dir/env" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then return 1; fi
    return 0
}

# Find Terraform projects recursively
find_terraform_projects() {
    local search_path="$1"
    local projects=()
    while IFS= read -r -d '' main_tf_file; do
        project_dir=$(dirname "$main_tf_file")
        if [ -d "$project_dir/env" ]; then
            if [ -n "$(find "$project_dir/env" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then
                projects+=("$project_dir")
            fi
        fi
    done < <(find "$search_path" -type f -name "main.tf" -not -path "*/modules/*" -print0 2>/dev/null || true)
    printf '%s\n' "${projects[@]}" | sort -u
}

# Get all environments dynamically
get_environments() {
    local project_dir="$1"
    local envs_dir="$project_dir/env/"
    if [ -d "$envs_dir" ]; then
        find "$envs_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
    else
        echo ""
    fi
}

get_first_four_chars() {
    local name="$1"
    echo "${name:0:4}" | tr '[:upper:]' '[:lower:]'
}

# Find matching backend config
find_matching_backend_config() {
    local project_dir="$1"
    local env="$2"
    local env_path="$project_dir/env/${env}"
    if [ ! -d "$env_path" ]; then echo ""; return; fi
    local env_prefix=$(get_first_four_chars "$env")
    for config_file in "${env_path}"/*.conf; do
        [ -f "$config_file" ] || continue
        local config_name=$(basename "$config_file" .conf)
        local config_prefix=$(get_first_four_chars "$config_name")
        if [ "$env_prefix" = "$config_prefix" ]; then
            echo "$config_file"
            return 0
        fi
    done
    for config_file in "${env_path}"/*.conf; do
        [ -f "$config_file" ] && echo "$config_file" && return 0
    done
    echo ""
}

# Find matching tfvars file
find_matching_tfvars_file() {
    local project_dir="$1"
    local env="$2"
    local config_path="$project_dir/config"
    if [ ! -d "$config_path" ]; then echo ""; return; fi
    local env_prefix=$(get_first_four_chars "$env")
    for tfvars_file in "${config_path}"/*.tfvars; do
        [ -f "$tfvars_file" ] || continue
        local tfvars_name=$(basename "$tfvars_file" .tfvars)
        local tfvars_prefix=$(get_first_four_chars "$tfvars_name")
        if [ "$env_prefix" = "$tfvars_prefix" ]; then
            echo "$tfvars_file"
            return 0
        fi
    done
    for tfvars_file in "${config_path}"/*.tfvars; do
        [ -f "$tfvars_file" ] && echo "$tfvars_file" && return 0
    done
    echo ""
}

get_project_name() {
    local project_dir="$1"
    project_dir="${project_dir#./}"
    project_dir="${project_dir#applications/}"
    project_dir="${project_dir#SPA/}"
    echo "$project_dir" | tr '/' '-'
}

get_relative_path_to_root() {
    local env_dir="$1"
    local project_dir="$2"
    local rel_path="${env_dir#$project_dir/}"
    local levels_deep=$(echo "$rel_path" | tr -cd '/' | wc -c)
    levels_deep=$((levels_deep + 1))
    if [ $levels_deep -eq 0 ]; then echo "."; else printf '../%.0s' $(seq 1 $levels_deep) | sed 's/.$//'; fi
}

ENV_FILE=$(mktemp)
BACKEND_FILE=$(mktemp)
TFVARS_FILE=$(mktemp)
PROJECT_INFO_FILE=$(mktemp)
ALL_PROJECTS_FILE=$(mktemp)

echo "Searching for Terraform projects in applications and SPA folders..."

if [ ! -d "applications" ] && [ ! -d "SPA" ]; then
    echo "Error: Neither 'applications' nor 'SPA' directory found"
    exit 1
fi

> "$ALL_PROJECTS_FILE"
[ -d "applications" ] && find_terraform_projects "applications" >> "$ALL_PROJECTS_FILE"
[ -d "SPA" ] && find_terraform_projects "SPA" >> "$ALL_PROJECTS_FILE"

sort -u -o "$ALL_PROJECTS_FILE" "$ALL_PROJECTS_FILE"

project_count=$(wc -l < "$ALL_PROJECTS_FILE")
echo "Found $project_count Terraform projects total"

# Discover environments and configs
while IFS= read -r project_dir; do
    [ -z "$project_dir" ] && continue
    if ! is_terraform_project "$project_dir"; then continue; fi
    environments=$(get_environments "$project_dir")
    echo "$environments" | while IFS= read -r env; do
        [ -z "$env" ] && continue
        backend_config=$(find_matching_backend_config "$project_dir" "$env")
        tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
        [ -n "$backend_config" ] && echo "${project_dir}|${env}|${backend_config}" >> "$BACKEND_FILE"
        [ -n "$tfvars_file" ] && echo "${project_dir}|${env}|${tfvars_file}" >> "$TFVARS_FILE"
    done
done < "$ALL_PROJECTS_FILE"

get_backend_config_for_project() {
    local project_dir="$1"
    local env="$2"
    awk -F'|' -v proj="$project_dir" -v env_name="$env" '$1 == proj && $2 == env_name {print $3}' "$BACKEND_FILE" | head -1
}

get_tfvars_file_for_project() {
    local project_dir="$1"
    local env="$2"
    awk -F'|' -v proj="$project_dir" -v env_name="$env" '$1 == proj && $2 == env_name {print $3}' "$TFVARS_FILE" | head -1
}

WORKFLOWS_FILE=$(mktemp)

while IFS= read -r project_dir; do
    [ -z "$project_dir" ] && continue
    if ! is_terraform_project "$project_dir"; then continue; fi
    project_name=$(get_project_name "$project_dir")
    environments=$(get_environments "$project_dir")
    echo "$environments" | while IFS= read -r env; do
        [ -z "$env" ] && continue
        env_path="$project_dir/env/${env}"
        [ ! -d "$env_path" ] && continue
        backend_config=$(get_backend_config_for_project "$project_dir" "$env")
        tfvars_file=$(get_tfvars_file_for_project "$project_dir" "$env")
        [ -z "$backend_config" ] && backend_config=$(find_matching_backend_config "$project_dir" "$env")
        [ -z "$tfvars_file" ] && tfvars_file=$(find_matching_tfvars_file "$project_dir" "$env")
        [ -z "$backend_config" ] || [ -z "$tfvars_file" ] && continue
        relative_to_root=$(get_relative_path_to_root "$env_path" "$project_dir")
        workflow_name="${project_name}-${env}-workflow"
        echo "$workflow_name" >> "$WORKFLOWS_FILE"
        echo "${project_dir}|${env}|${relative_to_root}|${workflow_name}" >> "$PROJECT_INFO_FILE"
        {
        echo "  - name: ${project_name}-${env}"
        echo "    dir: $env_path"
        echo "    autoplan:"
        echo "      enabled: false"
        echo "      when_modified:"
        echo "        - \"${relative_to_root}/*.tf\""
        echo "        - \"${relative_to_root}/*.tfvars\""
        echo "        - \"${relative_to_root}/config/*.tfvars\""
        echo "        - \"${relative_to_root}/env/*/*\""
        echo "    terraform_version: v1.6.6"
        echo "    workflow: ${workflow_name}"
        echo "    apply_requirements:"
        echo "      - approved"
        echo "      - mergeable"
        } >> atlantis.yaml
    done
done < "$ALL_PROJECTS_FILE"

# Generate workflows with role assumption
if [ -s "$PROJECT_INFO_FILE" ]; then
    cat >> atlantis.yaml <<EOF
workflows:
EOF

    while IFS='|' read -r project_dir env relative_to_root workflow_name; do
        [ -z "$project_dir" ] && continue
        backend_config=$(get_backend_config_for_project "$project_dir" "$env")
        tfvars_file=$(get_tfvars_file_for_project "$project_dir" "$env")
        [ -z "$backend_config" ] || [ -z "$tfvars_file" ] && continue
        backend_config_file=$(basename "$backend_config")
        tfvars_config_file=$(basename "$tfvars_file")
        [ -z "$relative_to_root" ] && relative_to_root="../.."

        {
        echo "  ${workflow_name}:"
        echo "    plan:"
        echo "      steps:"
        echo "        - run: |"
        echo "            # Map environment to role ARN"
        echo "            if [ \"$env\" = \"stage\" ]; then"
        echo "                ROLE_ARN=\"arn:aws:iam::569023477847:role/atlantis-cross-account-role-stage\""
        echo "            elif [ \"$env\" = \"prod\" ]; then"
        echo "                ROLE_ARN=\"arn:aws:iam::569023477847:role/atlantis-cross-account-role-prod\""
        echo "            fi"
        echo "            # Assume the role and export temporary credentials"
        echo "            CREDS_JSON=\$(aws sts assume-role --role-arn \$ROLE_ARN --role-session-name atlantis-session-$env --query 'Credentials' --output json)"
        echo "            export AWS_ACCESS_KEY_ID=\$(echo \$CREDS_JSON | jq -r '.AccessKeyId')"
        echo "            export AWS_SECRET_ACCESS_KEY=\$(echo \$CREDS_JSON | jq -r '.SecretAccessKey')"
        echo "            export AWS_SESSION_TOKEN=\$(echo \$CREDS_JSON | jq -r '.SessionToken')"
        echo "            echo \"Assumed role \$ROLE_ARN successfully\""
        echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/$relative_to_root\""
        echo "            rm -rf .terraform .terraform.lock.hcl"
        echo "            terraform init -backend-config=\"env/$env/$backend_config_file\" -reconfigure -lock=false -input=false"
        echo "            terraform plan -compact-warnings -var-file=\"config/$tfvars_config_file\" -lock-timeout=10m -out=\$PLANFILE"
        echo "    apply:"
        echo "      steps:"
        echo "        - run: |"
        echo "            cd \"\$(dirname \"\$PROJECT_DIR\")/$relative_to_root\""
        echo "            terraform apply -auto-approve \$PLANFILE"
        } >> atlantis.yaml
    done < "$PROJECT_INFO_FILE"
else
    cat >> atlantis.yaml <<EOF
workflows:
EOF
fi

workflow_count=$(sort -u "$WORKFLOWS_FILE" | wc -l)
echo "Generated $workflow_count unique workflows"

rm -f "$ENV_FILE" "$BACKEND_FILE" "$TFVARS_FILE" "$PROJECT_INFO_FILE" "$ALL_PROJECTS_FILE" "$WORKFLOWS_FILE"

echo "Generated atlantis.yaml successfully with $project_count projects and $workflow_count workflows"