#!/usr/bin/env bash
# Bring UAT back after uat-scale-down-cheap.sh (mirrors dev-resume pattern for UAT defaults).
# - Restores node group toward Terraform UAT defaults (min 1 / desired 2 / max 6)
# - Starts UAT RDS and waits
# - Scales core workloads to match module replicas (2) including web-canary when present
# - Re-upserts Route53 alias for app-uat
#
# Usage (repo root): ./infra/scripts/uat-resume-cheap.sh
#
# Optional overrides:
#   AWS_REGION=us-east-1
#   UAT_CLUSTER_NAME=claiset-uat
#   UAT_NODEGROUP_NAME=claiset-uat-default
#   UAT_NAMESPACE=uat
#   UAT_FRONTEND_HOST=app-uat.claiset.xyz
#   UAT_RDS_ID=claiset-uat-postgres
#   UAT_APP_REPLICAS=2   # scale web/items/outfits/schedule (and web-canary) to this count
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${UAT_CLUSTER_NAME:-claiset-uat}"
NODEGROUP="${UAT_NODEGROUP_NAME:-${CLUSTER}-default}"
NAMESPACE="${UAT_NAMESPACE:-uat}"
FRONTEND_HOST="${UAT_FRONTEND_HOST:-app-uat.claiset.xyz}"
RDS_ID="${UAT_RDS_ID:-claiset-uat-postgres}"
NODE_MIN="${UAT_NODE_MIN:-1}"
NODE_DESIRED="${UAT_NODE_DESIRED:-2}"
NODE_MAX="${UAT_NODE_MAX:-6}"
APP_REPLICAS="${UAT_APP_REPLICAS:-2}"

echo "Resuming UAT: cluster=${CLUSTER} namespace=${NAMESPACE} region=${REGION}"

echo "Step 1/5: Ensure nodegroup scaling (min=${NODE_MIN} desired=${NODE_DESIRED} max=${NODE_MAX})"
aws eks update-nodegroup-config \
  --region "${REGION}" \
  --cluster-name "${CLUSTER}" \
  --nodegroup-name "${NODEGROUP}" \
  --scaling-config "minSize=${NODE_MIN},desiredSize=${NODE_DESIRED},maxSize=${NODE_MAX}" >/dev/null
aws eks wait nodegroup-active \
  --region "${REGION}" \
  --cluster-name "${CLUSTER}" \
  --nodegroup-name "${NODEGROUP}"

echo "Step 2/5: Start RDS if needed (${RDS_ID})"
rds_status="$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${RDS_ID}" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)"
if [[ "${rds_status}" == "available" ]]; then
  echo "RDS already available."
else
  if [[ "${rds_status}" == "stopped" ]]; then
    aws rds start-db-instance --region "${REGION}" --db-instance-identifier "${RDS_ID}" >/dev/null
  fi
  echo "Waiting for RDS to become available..."
  aws rds wait db-instance-available --region "${REGION}" --db-instance-identifier "${RDS_ID}"
fi

echo "Step 3/5: Configure kubeconfig"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

echo "Step 4/5: Scale core UAT workloads (replicas=${APP_REPLICAS})"
kubectl -n "${NAMESPACE}" scale deployment web items outfits schedule --replicas="${APP_REPLICAS}" >/dev/null
if kubectl -n "${NAMESPACE}" get deployment web-canary >/dev/null 2>&1; then
  kubectl -n "${NAMESPACE}" scale deployment web-canary --replicas="${APP_REPLICAS}" >/dev/null
fi

echo "Step 5/5: Reconcile Route53 alias from current Ingress"
pushd "${ROOT_DIR}/infra/envs/uat" >/dev/null
EXPECTED_CLUSTER_NAME="${UAT_CLUSTER_NAME:-${CLUSTER}}" \
  DOMAIN_ROOT=claiset.xyz FRONTEND_SUBDOMAIN=app-uat UPDATE_APEX_DNS=false K8S_APP_NAMESPACE="${NAMESPACE}" \
  bash ../../scripts/route53-ingress-records-guard.sh
popd >/dev/null

echo "UAT resume complete."
echo "Frontend: https://${FRONTEND_HOST}"
