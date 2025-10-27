#!/usr/bin/env bash
set -euo pipefail
# repo-root-aware process script. Works no matter where it's invoked from.

usage() {
  cat <<EOF
Usage: $0 <env> [app_dir]
  env: staging | production | helia
  app_dir (optional): path to a single app directory (can be relative to repo root or absolute).
If app_dir is omitted, the script will scan the repository's application/ directory for main.tf files.
EOF
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

ENV="$1"
TARGET_ARG="${2:-}"

# Determine the directory where this script lives (script_dir) and treat that as repo root if it contains the application/ folder.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If SCRIPT_DIR contains application directory, assume SCRIPT_DIR is repo root. Otherwise assume repo root is parent of script dir.
if [[ -d "${SCRIPT_DIR}/application" ]]; then
  REPO_ROOT="${SCRIPT_DIR}"
elif [[ -d "${SCRIPT_DIR}/../application" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  # fallback to current working directory if nothing else
  REPO_ROOT="$(pwd)"
fi

# Resolve target app dir (if provided). Accept absolute or repo-root-relative paths.
TARGET_APP=""
if [[ -n "${TARGET_ARG:-}" ]]; then
  if [[ "${TARGET_ARG}" = /* ]]; then
    TARGET_APP="${TARGET_ARG}"
  else
    TARGET_APP="${REPO_ROOT}/${TARGET_ARG#./}"
  fi
elif [[ -n "${ATLANTIS_DIR:-}" ]]; then
  # ATLANTIS_DIR provided by Atlantis is repo-relative from the project dir; make it absolute relative to REPO_ROOT.
  if [[ "${ATLANTIS_DIR}" = /* ]]; then
    TARGET_APP="${ATLANTIS_DIR}"
  else
    TARGET_APP="${REPO_ROOT}/${ATLANTIS_DIR#./}"
  fi
fi

echo "=== STARTING processing for env='${ENV}' target='${TARGET_APP:-<all>}' repo_root='${REPO_ROOT}' at $(date) ==="

# collect app directories (absolute paths)
dirs=()
if [[ -n "$TARGET_APP" ]]; then
  if [[ -d "$TARGET_APP" ]]; then
    dirs+=("$(cd "$TARGET_APP" && pwd)")
  else
    echo "Target app directory not found: $TARGET_APP"
    exit 1
  fi
else
  # Portable find: search under REPO_ROOT/application for main.tf and get unique directories
  while IFS= read -r -d $'\0' f; do
    dirs+=("$(dirname "$f")")
  done < <(find "$REPO_ROOT/application" -type f -name "main.tf" -print0 2>/dev/null)
  # Deduplicate (sort -u)
  if [[ ${#dirs[@]} -gt 0 ]]; then
    mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | sort -u)
  fi
fi

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application directories found!"
  exit 1
fi

echo "Found ${#dirs[@]} application(s):"
for dd in "${dirs[@]}"; do echo " - $dd"; done

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"

for d in "${dirs[@]}"; do
  if [[ ! -f "$d/main.tf" ]]; then
    echo "Skipping $d (main.tf missing)"
    continue
  fi

  APP_NAME="$(basename "$d")"
  echo "=== Planning $APP_NAME ($ENV) in $d ==="

  # Resolve backend config: pick first .conf under env/<ENV> inside the app dir
  BACKEND_CONFIG_PATH=""
  if [[ -d "$d/env/$ENV" ]]; then
    for conf in "$d/env/$ENV"/*.conf; do
      if [[ -f "$conf" ]]; then
        # Make absolute
        BACKEND_CONFIG_PATH="$(cd "$(dirname "$conf")" && pwd)/$(basename "$conf")"
        break
      fi
    done
  fi

  if [[ -z "$BACKEND_CONFIG_PATH" ]]; then
    echo "Backend config not found under $d/env/$ENV"
    echo "Available backend configs for $d (if any):"
    find "$d/env" -type f -name "*.conf" 2>/dev/null || echo "No backend configs found at all for $d"
    continue
  fi

  # Resolve var-file name relative to each app dir
  if [[ "$ENV" == "staging" ]]; then
    VAR_FILE_REL="config/stage.tfvars"
  else
    VAR_FILE_REL="config/${ENV}.tfvars"
  fi

  if [[ ! -f "$d/$VAR_FILE_REL" ]]; then
    echo "Var file not found: $d/$VAR_FILE_REL"
    ls -la "$d/config" 2>/dev/null || echo "config directory not found for $d"
    continue
  fi

  # Clean previous init artifacts to be safe
  rm -rf "$d/.terraform" || true

  echo "Step 1: Initializing $d using backend config: $BACKEND_CONFIG_PATH"
  if ! timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG_PATH" -reconfigure -input=false; then
    echo "Init failed for $d"
    continue
  fi

  # Unique plan file in /tmp (absolute)
  SAFE_DIR_NAME="$(echo "$d" | sed 's|/|_|g' | sed 's/[^A-Za-z0-9_.-]/_/g')"
  PLAN="/tmp/${SAFE_DIR_NAME}_${ENV}.tfplan"
  echo "Step 2: Planning $d -> $PLAN (var-file: $VAR_FILE_REL)"
  if ! timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE_REL" -out="$PLAN"; then
    echo "Plan failed for $d"
    continue
  fi

  # record absolute directory + absolute plan path
  echo "${d}|${PLAN}" >> "$PLANLIST"
  echo "Successfully planned $APP_NAME ($ENV) -> $PLAN"
done

echo "=== COMPLETED processing for env='${ENV}' at $(date) ==="
echo "Plan list created: $PLANLIST"
cat "$PLANLIST" 2>/dev/null || echo "No plan files created"