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

  # Best-effort pre-cleanup in cluster to reduce ALB/ENI dependency leftovers that block subnet/IGW destroy.
  CLUSTER_NAME="${EXPECTED_CLUSTER_NAME:-claiset-${ENV}}"
  if command -v aws >/dev/null 2>&1 && command -v kubectl >/dev/null 2>&1; then
    if aws eks describe-cluster --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
      echo "Pre-cleanup (${ENV}): cluster=${CLUSTER_NAME} namespace=${ENV}"
      aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null || true
      kubectl delete ingress claiset -n "${ENV}" --ignore-not-found=true --wait=true || true
      # Remove any LB Services that could keep ENIs/EIPs attached.
      kubectl get svc -n "${ENV}" -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | while IFS= read -r svc; do
            [[ -n "${svc}" ]] || continue
            kubectl delete svc "${svc}" -n "${ENV}" --ignore-not-found=true --wait=true || true
          done
      kubectl wait --for=delete ingress/claiset -n "${ENV}" --timeout=120s 2>/dev/null || true
    fi
  fi

  (
    cd "${ENV_DIR}"
    terraform init \
      -backend-config="bucket=${STATE_BUCKET}" \
      -backend-config="key=envs/${ENV}/terraform.tfstate" \
      -backend-config="region=${AWS_REGION}" \
      -backend-config="dynamodb_table=${LOCK_TABLE}" \
      -backend-config="encrypt=true"

    # Phase 1: tear down Kubernetes/platform resources first to release ALB/ENI/EIP dependencies.
    # If these modules are already gone, continue to full destroy.
    echo "Phase 1 destroy (${ENV}): app/platform resources"
    terraform destroy "${DESTROY_OPTS[@]}" \
      -target=module.app_bluegreen \
      -target=module.platform || true

    # Phase 2: full environment destroy.
    echo "Phase 2 destroy (${ENV}): full environment"
    if ! terraform destroy "${DESTROY_OPTS[@]}"; then
      echo "Full destroy failed for ${ENV}; waiting and retrying once for eventual-consistency dependencies..."
      sleep 20
      terraform destroy "${DESTROY_OPTS[@]}"
    fi
  )
done

echo
echo "All requested environments processed."

