#!/usr/bin/env bash
# Destroy one or more environments to stop AWS charges.
#
# Usage (from repo root):
#   export TF_STATE_BUCKET=your-bootstrap-bucket
#   export TF_LOCK_TABLE=your-bootstrap-lock-table
#   export AWS_REGION=us-east-1   # or your region
#   ./infra/scripts/terraform-destroy-all.sh           # destroys dev,qa,uat,prod (asks for confirmation)
#   ./infra/scripts/terraform-destroy-all.sh dev qa    # only destroy specific envs
#
# Notes:
# - Uses the same backend layout as promotion.yml: envs/<env>/terraform.tfstate
# - In CI, set TF_DESTROY_AUTO_APPROVE=1 and pass env names (e.g. qa) to skip the prompt.
# - Run this from your laptop, not inside GitHub Actions (unless TF_DESTROY_AUTO_APPROVE=1).
# - Make sure no CI job is currently running terraform for these envs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STATE_BUCKET="${TF_STATE_BUCKET:-}"
LOCK_TABLE="${TF_LOCK_TABLE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "${STATE_BUCKET}" || -z "${LOCK_TABLE}" ]]; then
  echo "TF_STATE_BUCKET and TF_LOCK_TABLE must be set in the environment." >&2
  echo "Example:" >&2
  echo "  export TF_STATE_BUCKET=claiset-tf-state-... " >&2
  echo "  export TF_LOCK_TABLE=claiset-tf-locks" >&2
  exit 1
fi

ENVS=("$@")
if [[ ${#ENVS[@]} -eq 0 ]]; then
  ENVS=(dev qa uat prod)
fi

DESTROY_OPTS=()
if [[ "${TF_DESTROY_AUTO_APPROVE:-0}" == "1" ]]; then
  echo "TF_DESTROY_AUTO_APPROVE=1: destroying without confirmation: ${ENVS[*]}"
  DESTROY_OPTS=(-auto-approve)
else
  echo "About to destroy environments: ${ENVS[*]}"
  read -r -p "Type 'yes' to continue: " CONFIRM
  if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

for ENV in "${ENVS[@]}"; do
  ENV_DIR="${ROOT_DIR}/infra/envs/${ENV}"
  if [[ ! -d "${ENV_DIR}" ]]; then
    echo "Skipping ${ENV}: ${ENV_DIR} does not exist."
    continue
  fi

  echo
  echo "=== Destroying ${ENV} ==="
  (
    cd "${ENV_DIR}"
    terraform init \
      -backend-config="bucket=${STATE_BUCKET}" \
      -backend-config="key=envs/${ENV}/terraform.tfstate" \
      -backend-config="region=${AWS_REGION}" \
      -backend-config="dynamodb_table=${LOCK_TABLE}" \
      -backend-config="encrypt=true"

    terraform destroy "${DESTROY_OPTS[@]}"
  )
done

echo
echo "All requested environments processed."

