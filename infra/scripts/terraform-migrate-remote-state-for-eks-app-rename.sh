#!/usr/bin/env bash
# Applies remote-backend init + one-time module address renames for a single env workspace.
# Run from anywhere; requires terraform on PATH + AWS credentials for the state bucket account.
#
# Usage:
#   export TF_STATE_BUCKET=... TF_LOCK_TABLE=...   # same as GitHub Actions secrets
#   export AWS_REGION=us-east-1                    # optional, default below
#
#   bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh dev
#   bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh qa
#   bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh prod
#   # Optional if an old state file remains in S3:
#   bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh uat
#
set -euo pipefail

ENV="${1:?usage: $0 <dev|qa|uat|prod>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUCKET="${TF_STATE_BUCKET:?set TF_STATE_BUCKET (S3 backend bucket)}"
LOCK="${TF_LOCK_TABLE:?set TF_LOCK_TABLE (DynamoDB lock table)}"
REGION="${AWS_REGION:-us-east-1}"

case "${ENV}" in
dev | qa | uat | prod) ;;
*)
  echo "Unknown env: ${ENV} (use dev|qa|uat|prod)" >&2
  exit 1
  ;;
esac

WORKDIR="${INFRA_ROOT}/envs/${ENV}"
if [[ ! -d "${WORKDIR}" ]]; then
  echo "Missing ${WORKDIR}" >&2
  exit 1
fi

echo ">>> ${ENV}: terraform init (-reconfigure) against remote backend"
(cd "${WORKDIR}" && terraform init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=envs/${ENV}/terraform.tfstate" \
  -backend-config="region=${REGION}" \
  -backend-config="dynamodb_table=${LOCK}" \
  -backend-config="encrypt=true")

echo ">>> ${ENV}: state mv module.app_bluegreen → module.eks_app (if present)"
(cd "${WORKDIR}" && bash "${SCRIPT_DIR}/terraform-state-mv-module-to-eks-app.sh")

echo ">>> ${ENV}: done. Sanity check:"
(cd "${WORKDIR}" && terraform plan -input=false -lock-timeout=300 -no-color 2>&1 | head -80) || true
echo "... (truncate) Run full plan yourself: cd ${WORKDIR} && terraform plan"
