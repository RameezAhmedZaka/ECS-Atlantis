#!/usr/bin/env bash
set -euo pipefail
ENV="$1"
TARGET_ARG="${2:-}"

# Determine script/ repo root as before
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${SCRIPT_DIR}/application" ]]; then
  REPO_ROOT="${SCRIPT_DIR}"
elif [[ -d "${SCRIPT_DIR}/../application" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  REPO_ROOT="$(pwd)"
fi

LOG="/tmp/atlantis_debug_${ENV}.log"
: > "$LOG"
echo "DEBUG: repo_root=$REPO_ROOT ENV=$ENV TARGET_ARG=${TARGET_ARG:-<none>} ATLANTIS_DIR=${ATLANTIS_DIR:-<unset>}" | tee -a "$LOG"

# Resolve target app as absolute path if provided
TARGET_APP=""
if [[ -n "${TARGET_ARG:-}" ]]; then
  if [[ "${TARGET_ARG}" = /* ]]; then TARGET_APP="$TARGET_ARG"; else TARGET_APP="${REPO_ROOT}/${TARGET_ARG#./}"; fi
elif [[ -n "${ATLANTIS_DIR:-}" ]]; then
  if [[ "${ATLANTIS_DIR}" = /* ]]; then TARGET_APP="${ATLANTIS_DIR}"; else TARGET_APP="${REPO_ROOT}/${ATLANTIS_DIR#./}"; fi
fi
echo "DEBUG: resolved TARGET_APP=$TARGET_APP" | tee -a "$LOG"

# Collect app dirs
dirs=()
if [[ -n "$TARGET_APP" ]]; then
  if [[ -d "$TARGET_APP" ]]; then dirs+=("$(cd "$TARGET_APP" && pwd)"); else echo "Target app not found: $TARGET_APP" | tee -a "$LOG"; exit 1; fi
else
  while IFS= read -r -d $'\0' f; do dirs+=("$(dirname "$f")"); done < <(find "$REPO_ROOT/application" -type f -name main.tf -print0 2>/dev/null)
  if [[ ${#dirs[@]} -gt 0 ]]; then mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | sort -u); fi
fi

echo "DEBUG: found ${#dirs[@]} dirs" | tee -a "$LOG"
for d in "${dirs[@]}"; do
  echo "DEBUG: checking app dir: $d" | tee -a "$LOG"
  echo "DEBUG: listing $d:" | tee -a "$LOG"
  ls -la "$d" 2>/dev/null | tee -a "$LOG"
done

PLANLIST="/tmp/atlantis_planfiles_${ENV}.lst"
: > "$PLANLIST"
echo "DEBUG: planlist will be $PLANLIST" | tee -a "$LOG"

for d in "${dirs[@]}"; do
  echo "----" | tee -a "$LOG"
  echo "DEBUG: processing $d" | tee -a "$LOG"
  # backend config discovery
  if [[ -d "$d/env/$ENV" ]]; then
    found=false
    for conf in "$d/env/$ENV"/*.conf; do
      if [[ -f "$conf" ]]; then
        echo "DEBUG: found backend conf: $conf" | tee -a "$LOG"
        # absolute
        if [[ "$conf" = /* ]]; then bc="$conf"; else bc="$(pwd)/$conf"; fi
        echo "DEBUG: using absolute backend-config: $bc" | tee -a "$LOG"
        found=true
        break
      fi
    done
    $found || echo "DEBUG: no .conf files in $d/env/$ENV" | tee -a "$LOG"
  else
    echo "DEBUG: no env dir $d/env/$ENV" | tee -a "$LOG"
  fi

  # var-file
  if [[ "$ENV" == "staging" ]]; then vf="config/stage.tfvars"; else vf="config/${ENV}.tfvars"; fi
  if [[ -f "$d/$vf" ]]; then echo "DEBUG: var file exists: $d/$vf" | tee -a "$LOG"; else echo "DEBUG: var file MISSING: $d/$vf" | tee -a "$LOG"; fi

  # Try init and plan but capture success/failure without exiting entire script
  rm -rf "$d/.terraform" || true
  echo "DEBUG: running terraform init -chdir=$d -backend-config=$bc" | tee -a "$LOG"
  if timeout 60 terraform -chdir="$d" init -upgrade -backend-config="$bc" -reconfigure -input=false 2>&1 | tee -a "$LOG"; then
    echo "DEBUG: init OK for $d" | tee -a "$LOG"
    SAFE=$(echo "$d" | sed 's|/|_|g' | sed 's/[^A-Za-z0-9_.-]/_/g')
    PLAN="/tmp/${SAFE}_${ENV}.tfplan"
    echo "DEBUG: running terraform plan -chdir=$d -var-file=$vf -out=$PLAN" | tee -a "$LOG"
    if timeout 120 terraform -chdir="$d" plan -input=false -lock-timeout=5m -var-file="$vf" -out="$PLAN" 2>&1 | tee -a "$LOG"; then
      echo "DEBUG: plan created $PLAN" | tee -a "$LOG"
      echo "${d}|${PLAN}" >> "$PLANLIST"
    else
      echo "DEBUG: plan FAILED for $d" | tee -a "$LOG"
    fi
  else
    echo "DEBUG: init FAILED for $d" | tee -a "$LOG"
  fi
done

echo "DEBUG: final planlist content:" | tee -a "$LOG"
cat "$PLANLIST" 2>/dev/null | tee -a "$LOG"
echo "WROTE debug log to $LOG"