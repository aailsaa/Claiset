#!/usr/bin/env bash
# Destroy promotion environments (qa, uat, prod) to cut most recurring cost,
# while keeping dev up.
#
# Usage (from repo root):
#   export TF_STATE_BUCKET=your-bootstrap-bucket
#   export TF_LOCK_TABLE=your-bootstrap-lock-table
#   export AWS_REGION=us-east-1   # or your region
#   ./infra/scripts/terraform-destroy-nonprod.sh
#
# This script is a thin wrapper around terraform-destroy-all.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
export TF_LOCK_TABLE="${TF_LOCK_TABLE:-}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "${TF_STATE_BUCKET}" || -z "${TF_LOCK_TABLE}" ]]; then
  echo "TF_STATE_BUCKET and TF_LOCK_TABLE must be set in the environment." >&2
  exit 1
fi

"${ROOT_DIR}/infra/scripts/terraform-destroy-all.sh" qa uat prod

