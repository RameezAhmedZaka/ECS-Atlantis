#!/usr/bin/env bash
set -euo pipefail

# Hardened, repo-root-aware process-application script
# Usage: ./process-application.sh <env> [app_dir]
# Produces /tmp/atlantis_planfiles_<env>.lst and debug log /tmp/atlantis_debug_<env>.log

usage() {
  cat <<EOF
Usage: $0 <env> [app_dir]
  env: staging | production | helia
  app_dir (optional): path to single app dir (absolute or repo-root-relative)
EOF
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

ENV="$1"
TARGET_ARG="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${SCRIPT_DIR}/application" ]]; then
  REPO_ROOT="${SCRIPT_DIR}"
elif [[ -d "${SCRIPT_DIR}/../application" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  REPO_ROOT="$(pwd)"
fi

DEBUG_LOG="/tmp/atlantis_debug_${ENV}.log"
: > "$DEBUG_LOG"
echo "DEBUG: script_dir=${SCRIPT_DIR} repo_root=${REPO_ROOT} env=${ENV} target_arg=${TARGET_ARG:-<none>} ATLANTIS_DIR=${ATLANTIS_DIR:-<unset>}" | tee -a "$DEBUG_LOG"

# Safety limits
MAX_DIRS=500
MAX_CONSECUTIVE_FAILURES=10

# Resolve target app absolute path if provided
TARGET_APP=""
if [[ -n "${TARGET_ARG:-}" ]]; then
  if [[ "${TARGET_ARG}" = /* ]]; then
    TARGET_APP="${TARGET_ARG}"
  else
    TARGET_APP="${REPO_ROOT}/${TARGET_ARG#./}"
  fi
elif [[ -n "${ATLANTIS_DIR:-}" ]]; then
  if [[ "${ATLANTIS_DIR}" = /* ]]; then
    TARGET_APP="${ATLANTIS_DIR}"
  else
    TARGET_APP="${REPO_ROOT}/${ATLANTIS_DIR#./}"
  fi
fi

echo "DEBUG: resolved TARGET_APP=${TARGET_APP:-<all>}" | tee -a "$DEBUG_LOG"

# Build list of app dirs (absolute)
dirs=()
if [[ -n "$TARGET_APP" ]]; then
  if [[ -d "$TARGET_APP" ]]; then
    dirs+=("$(cd "$TARGET_APP" && pwd)")
  else
    echo "ERROR: Target app directory not found: $TARGET_APP" | tee -a "$DEBUG_LOG"
    exit 1
  fi
else
  while IFS= read -r -d $'\0' f; do
    dirs+=("$(dirname "$f")")
    if [[ ${#dirs[@]} -ge $MAX_DIRS ]]; then
      echo "DEBUG: reached MAX_DIRS ($MAX_DIRS), stopping directory collection" | tee -a "$DEBUG_LOG"
      break
    fi
  done < <(find "$REPO_ROOT/application" -type f -name "main.tf" -print0 2>/dev/null)
  if [[ ${#dirs[@]} -gt 0 ]]; then
    mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | sort -u)
  fi
fi

echo "DEBUG: discovered ${#dirs[@]} app directories" | tee -a "$DEBUG_LOG"
for dd in "${dirs[@]}"; do echo "DEBUG: app: $dd"; done | tee -a "$DEBUG_LOG"

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No application directories found!" | tee -a "$DEBUG_LOG"
  exit 1
fi

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
consecutive_failures=0
counter=0

for d in "${dirs[@]}"; do
  counter=$((counter+1))
  echo "=== [$counter/${#dirs[@]}] Processing app: $d ===" | tee -a "$DEBUG_LOG"

  if [[ $consecutive_failures -ge $MAX_CONSECUTIVE_FAILURES ]]; then
    echo "ERROR: aborting due to $consecutive_failures consecutive failures" | tee -a "$DEBUG_LOG"
    break
  fi

  if [[ ! -f "$d/main.tf" ]]; then
    echo "Skipping $d (main.tf missing)" | tee -a "$DEBUG_LOG"
    consecutive_failures=0
    continue
  fi

  # Initialize backend-config variable safely
  BACKEND_CONFIG_PATH=""
  if [[ -d "$d/env/$ENV" ]]; then
    for conf in "$d/env/$ENV"/*.conf; do
      if [[ -f "$conf" ]]; then
        BACKEND_CONFIG_PATH="$(cd "$(dirname "$conf")" && pwd)/$(basename "$conf")"
        break
      fi
    done
  fi

  if [[ -z "${BACKEND_CONFIG_PATH:-}" ]]; then
    echo "WARN: backend config not found under $d/env/$ENV - skipping" | tee -a "$DEBUG_LOG"
    consecutive_failures=$((consecutive_failures+1))
    continue
  fi

  # var file relative path inside app dir
  if [[ "$ENV" == "staging" ]]; then
    VAR_FILE_REL="config/stage.tfvars"
  else
    VAR_FILE_REL="config/${ENV}.tfvars"
  fi

  if [[ ! -f "$d/$VAR_FILE_REL" ]]; then
    echo "WARN: var file missing: $d/$VAR_FILE_REL - skipping" | tee -a "$DEBUG_LOG"
    consecutive_failures=$((consecutive_failures+1))
    continue
  fi

  consecutive_failures=0

  rm -rf "$d/.terraform" || true

  echo "DEBUG: initializing terraform in $d using backend $BACKEND_CONFIG_PATH" | tee -a "$DEBUG_LOG"
  if ! timeout 120 terraform -chdir="$d" init -upgrade -backend-config="$BACKEND_CONFIG_PATH" -reconfigure -input=false 2>&1 | tee -a "$DEBUG_LOG"; then
    echo "ERROR: init failed for $d (see log). Common cause: backend S3 bucket does not exist or creds missing." | tee -a "$DEBUG_LOG"
    consecutive_failures=$((consecutive_failures+1))
    continue
  fi

  SAFE_DIR_NAME="$(echo "$d" | sed 's|/|_|g' | sed 's/[^A-Za-z0-9_.-]/_/g')"
  PLAN="/tmp/${SAFE_DIR_NAME}_${ENV}.tfplan"
  echo "DEBUG: running terraform plan for $d -> $PLAN (var-file: $VAR_FILE_REL)" | tee -a "$DEBUG_LOG"

  if ! timeout 300 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$VAR_FILE_REL" -out="$PLAN" 2>&1 | tee -a "$DEBUG_LOG"; then
    echo "ERROR: plan failed for $d (see log)" | tee -a "$DEBUG_LOG"
    rm -f "$PLAN" || true
    consecutive_failures=$((consecutive_failures+1))
    continue
  fi

  echo "${d}|${PLAN}" >> "$PLANLIST"
  echo "OK: planned $d -> $PLAN" | tee -a "$DEBUG_LOG"
  consecutive_failures=0
done

echo "Completed processing. Planlist: $PLANLIST" | tee -a "$DEBUG_LOG"
echo "Planlist contents:" | tee -a "$DEBUG_LOG"
cat "$PLANLIST" 2>/dev/null | tee -a "$DEBUG_LOG" || true
echo "Wrote debug log to $DEBUG_LOG"