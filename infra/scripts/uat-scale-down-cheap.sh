#!/usr/bin/env bash
# Park UAT workloads to save cost during idle breaks (same idea as dev-scale-down-cheap.sh).
# - Scales core app Deployments to 0 (including web-canary when present)
# - Stops UAT RDS when possible
# - Shrinks the UAT node group
#
# Usage (repo root): ./infra/scripts/uat-scale-down-cheap.sh
#
# Resume: ./infra/scripts/uat-resume-cheap.sh
#
# Note: kubectl scale may be overwritten by the next Terraform apply to match eks_app.replicas.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${UAT_CLUSTER_NAME:-claiset-uat}"
NODEGROUP="${UAT_NODEGROUP_NAME:-${CLUSTER}-default}"
NAMESPACE="${UAT_NAMESPACE:-uat}"
RDS_ID="${UAT_RDS_ID:-claiset-uat-postgres}"
NODE_MIN="${UAT_NODE_MIN:-1}"
NODE_DESIRED="${UAT_NODE_DESIRED:-1}"
NODE_MAX="${UAT_NODE_MAX:-2}"

echo "Parking UAT: cluster=${CLUSTER} namespace=${NAMESPACE} region=${REGION}"

echo "Step 1/4: kubeconfig"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

echo "Step 2/4: Scale Deployments (web, items, outfits, schedule → 0; web-canary if present)"
kubectl -n "${NAMESPACE}" scale deployment web items outfits schedule --replicas=0 >/dev/null || true
if kubectl -n "${NAMESPACE}" get deployment web-canary >/dev/null 2>&1; then
  kubectl -n "${NAMESPACE}" scale deployment web-canary --replicas=0 >/dev/null || true
fi

echo "Step 3/4: Stop RDS if running (${RDS_ID})"
if rds_status="$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${RDS_ID}" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)"; then
  if [[ "${rds_status}" == "stopped" ]] || [[ "${rds_status}" == "stopping" ]]; then
    echo "RDS already stopped or stopping."
  elif [[ "${rds_status}" == "available" ]]; then
    aws rds stop-db-instance --region "${REGION}" --db-instance-identifier "${RDS_ID}" >/dev/null || true
    echo "Stop requested (may take minutes)."
  else
    echo "RDS status=${rds_status} — not stopping automatically."
  fi
else
  echo "RDS instance not found (${RDS_ID}); skip."
fi

echo "Step 4/4: Shrink nodegroup (min=${NODE_MIN} desired=${NODE_DESIRED} max=${NODE_MAX})"
AWS_REGION="${REGION}" bash "${ROOT_DIR}/infra/scripts/eks-burst-scale.sh" "${CLUSTER}" "${NODEGROUP}" "${NODE_MIN}" "${NODE_DESIRED}" "${NODE_MAX}"

echo "UAT parked."
echo "To bring UAT back: ${ROOT_DIR}/infra/scripts/uat-resume-cheap.sh"
