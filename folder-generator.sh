
#!/bin/bash
set -euo pipefail

echo "Scanning for Terraform projects and updating provider configuration..."

# Function to check if a directory is a Terraform project (has env directory and main.tf)
is_terraform_project() {
    local dir="$1"
    # Must have env directory to be a deployable project
    if [ ! -d "$dir/env" ]; then
        return 1
    fi
    # Must have main.tf
    if [ ! -f "$dir/main.tf" ]; then
        return 1
    fi
    # Must have at least one environment subdirectory
    if [ -z "$(find "$dir/env" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then
        return 1
    fi
    return 0
}

# Function to find all Terraform projects recursively (excluding modules)
find_terraform_projects() {
    local search_path="$1"
    local projects=()
    
    # Find all directories that contain main.tf AND have an env directory
    while IFS= read -r -d '' main_tf_file; do
        project_dir=$(dirname "$main_tf_file")
        
        # Check if this is a project (has env directory)
        if [ -d "$project_dir/env" ]; then
            # Check if env directory has at least one subdirectory
            if [ -n "$(find "$project_dir/env" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)" ]; then
                projects+=("$project_dir")
            fi
        fi
    done < <(find "$search_path" -type f -name "main.tf" -not -path "*/modules/*" -print0 2>/dev/null || true)
    
    # Return unique projects
    printf '%s\n' "${projects[@]}" | sort -u
}

# Function to find the variable file (could be variable.tf or variables.tf)
find_variable_file() {
    local project_dir="$1"
    
    if [ -f "$project_dir/variables.tf" ]; then
        echo "$project_dir/variables.tf"
    elif [ -f "$project_dir/variable.tf" ]; then
        echo "$project_dir/variable.tf"
    else
        # Default to variables.tf if neither exists
        echo "$project_dir/variables.tf"
    fi
}

# SUPER SIMPLE APPROACH - Just add the assume_role block after the first {
update_providers_tf() {
  local provider_file="$1"
  local temp_file="${provider_file}.tmp"

  echo "  Updating $provider_file"

  if [ ! -f "$provider_file" ]; then
    echo "    Warning: Provider file not found, skipping"
    return 1
  fi

  awk '
    function count_char(str, ch,   i,c) {
      c=0
      for (i=1; i<=length(str); i++) if (substr(str,i,1)==ch) c++
      return c
    }

    BEGIN {
      in_aws_provider = 0
      depth = 0
      saw_assume_role = 0
      buffer_len = 0
      injected_total = 0
    }

    function flush_provider_block(   i) {
      if (buffer_len == 0) return

      if (saw_assume_role == 1) {
        for (i=1; i<=buffer_len; i++) print buffer[i]
      } else {
        # inject after first line: provider "aws" {
        print buffer[1]
        print "  assume_role {"
        print "    role_arn = var.assume_role_arn"
        print "  }"
        for (i=2; i<=buffer_len; i++) print buffer[i]
        injected_total++
      }

      delete buffer
      buffer_len = 0
      in_aws_provider = 0
      depth = 0
      saw_assume_role = 0
    }

    {
      line = $0

      # Start of provider "aws" block
      if (line ~ /^[[:space:]]*provider[[:space:]]+"aws"[[:space:]]*{[[:space:]]*$/) {
        flush_provider_block()

        in_aws_provider = 1
        depth = 1
        saw_assume_role = 0

        buffer_len++
        buffer[buffer_len] = line
        next
      }

      # If buffering an aws provider block, collect lines and track depth
      if (in_aws_provider == 1) {
        if (line ~ /^[[:space:]]*assume_role[[:space:]]*{/) {
          saw_assume_role = 1
        }

        depth += count_char(line, "{")
        depth -= count_char(line, "}")

        buffer_len++
        buffer[buffer_len] = line

        if (depth <= 0) {
          flush_provider_block()
        }
        next
      }

      # Outside provider blocks
      print line
    }

    END {
      flush_provider_block()
    }
  ' "$provider_file" > "$temp_file" || {
    rm -f "$temp_file"
    echo "    Failed processing file with awk"
    return 1
  }

  mv "$temp_file" "$provider_file"
  echo "    Successfully updated all AWS provider blocks with assume_role where missing"
  return 0
}

# Function to update or create variable file with assume_role_arn variable
update_variable_file() {
    local variable_file="$1"
    
    echo "  Updating $variable_file"
    
    # Check if variable already exists in the file
    if [ -f "$variable_file" ] && grep -q "variable[[:space:]]*\"assume_role_arn\"" "$variable_file"; then
        echo "    variable 'assume_role_arn' already exists, skipping"
        return 0
    fi
    
    # If variable file exists, append to it, otherwise create new file
    if [ -f "$variable_file" ]; then
        # Append to existing file
        {
        echo ""
        echo 'variable "assume_role_arn" {'
        echo '  description = "Role for cross account deployment"'
        echo '  type        = string'
        echo '  default     = null'
        echo '}'
        } >> "$variable_file"
    else
        # Create new file
        {
        echo '# Variables'
        echo ''
        echo 'variable "assume_role_arn" {'
        echo '  description = "Role for cross account deployment"'
        echo '  type        = string'
        echo '  default     = null'
        echo '}'
        } > "$variable_file"
    fi
    
    echo "    Added variable 'assume_role_arn' to $(basename "$variable_file")"
    return 0
}

# Main execution
ALL_PROJECTS_FILE=$(mktemp)
UPDATED_PROJECTS_FILE=$(mktemp)

# Check if at least one of the directories exists
if [ ! -d "applications" ] && [ ! -d "SPA" ]; then
    echo "Error: Neither 'applications' nor 'SPA' directory found in current path"
    exit 1
fi

# Find all Terraform projects from both folders
> "$ALL_PROJECTS_FILE"

if [ -d "applications" ]; then
    echo "Searching in applications folder..."
    while IFS= read -r project; do
        echo "$project" >> "$ALL_PROJECTS_FILE"
    done < <(find_terraform_projects "applications")
fi

if [ -d "SPA" ]; then
    echo "Searching in SPA folder..."
    while IFS= read -r project; do
        echo "$project" >> "$ALL_PROJECTS_FILE"
    done < <(find_terraform_projects "SPA")
fi

# Sort and deduplicate projects
sort -u -o "$ALL_PROJECTS_FILE" "$ALL_PROJECTS_FILE"

# Count projects found
project_count=$(wc -l < "$ALL_PROJECTS_FILE" | tr -d ' ')
echo "Found $project_count Terraform projects total"
echo ""

# Process each project
updated_count=0
skipped_count=0
error_count=0

while IFS= read -r project_dir || [ -n "$project_dir" ]; do
    [ -z "$project_dir" ] && continue
    
    echo "Processing project: $project_dir"
    
    # Double-check it's a valid project
    if ! is_terraform_project "$project_dir"; then
        echo "  Skipping - not a valid Terraform project"
        skipped_count=$((skipped_count + 1))
        continue
    fi
    
    # Look for provider file
    provider_file=""
    if [ -f "$project_dir/providers.tf" ]; then
        provider_file="$project_dir/providers.tf"
        echo "  Found providers.tf"
    elif [ -f "$project_dir/provider.tf" ]; then
        provider_file="$project_dir/provider.tf"
        echo "  Found provider.tf"
    else
        # Look for any tf file that contains AWS provider
        while IFS= read -r tf_file; do
            if grep -q "provider.*aws" "$tf_file"; then
                provider_file="$tf_file"
                echo "  Found AWS provider in: $(basename "$tf_file")"
                break
            fi
        done < <(find "$project_dir" -maxdepth 1 -name "*.tf")
    fi
    
    if [ -z "$provider_file" ]; then
        echo "  ✗ No provider file with AWS provider found"
        error_count=$((error_count + 1))
        echo ""
        continue
    fi
    
    # Update the provider file
    if update_providers_tf "$provider_file"; then
        # Find the appropriate variable file
        variable_file=$(find_variable_file "$project_dir")
        
        # Update the variable file
        if update_variable_file "$variable_file"; then
            echo "  ✓ Successfully updated $project_dir"
            echo "$project_dir" >> "$UPDATED_PROJECTS_FILE"
            updated_count=$((updated_count + 1))
        else
            echo "  ✗ Failed to update variable file in $project_dir"
            error_count=$((error_count + 1))
        fi
    else
        echo "  ✗ Failed to update provider file in $project_dir"
        error_count=$((error_count + 1))
    fi
    
    echo ""
done < "$ALL_PROJECTS_FILE"

# Summary
echo "=========================================="
echo "Update Complete!"
echo "=========================================="
echo "Total projects found: $project_count"
echo "Successfully updated: $updated_count"
echo "Skipped: $skipped_count"
echo "Errors: $error_count"
echo ""

if [ $updated_count -gt 0 ]; then
    echo "Updated projects:"
    while IFS= read -r project; do
        echo "  - $project"
    done < "$UPDATED_PROJECTS_FILE"
fi

# Clean up
rm -f "$ALL_PROJECTS_FILE" "$UPDATED_PROJECTS_FILE"

echo ""
echo "Done!"

