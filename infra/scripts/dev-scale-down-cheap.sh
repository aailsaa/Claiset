#!/usr/bin/env bash
# Park dev workloads to reduce cost while you prove rollouts elsewhere (e.g. UAT).
# CI runs a pre-burst before dev Terraform apply so min_size (2) is never applied while desired=1.
# - Scales core app Deployments to 0
# - Stops dev RDS when possible
# - Shrinks the dev nodegroup (kube-system / platform DaemonSets still consume capacity)
#
# Usage (repo root): ./infra/scripts/dev-scale-down-cheap.sh
#
# Next time you want dev again: infra/scripts/dev-resume-cheap.sh
#
# Note: kubectl scale fights the next terraform apply unless it matches eks_app.replicas —
# safe for intentional "cold storage" gaps between applies.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${DEV_CLUSTER_NAME:-claiset-dev}"
NODEGROUP="${DEV_NODEGROUP_NAME:-${CLUSTER}-default}"
NAMESPACE="${DEV_NAMESPACE:-dev}"
RDS_ID="${DEV_RDS_ID:-claiset-dev-postgres}"
NODE_MIN="${DEV_NODE_MIN:-1}"
NODE_DESIRED="${DEV_NODE_DESIRED:-1}"
NODE_MAX="${DEV_NODE_MAX:-2}"

echo "Parking dev: cluster=${CLUSTER} namespace=${NAMESPACE} region=${REGION}"

echo "Step 1/4: kubeconfig"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

echo "Step 2/4: Scale Deployments (web/items/outfits/schedule → 0)"
kubectl -n "${NAMESPACE}" scale deployment web items outfits schedule --replicas=0 >/dev/null || true

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

echo "Dev parked."
echo "To bring dev back (nodes + RDS + app): ${ROOT_DIR}/infra/scripts/dev-resume-cheap.sh"
