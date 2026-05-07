#!/usr/bin/env bash
# Bring dev back to a low-cost but usable state.
# - Keeps EKS nodegroup small
# - Starts dev RDS and waits for availability
# - Scales core app deployments up
# - Re-upserts Route53 alias from current Ingress ALB
#
# Usage (from repo root):
#   ./infra/scripts/dev-resume-cheap.sh
#
# Optional overrides:
#   AWS_REGION=us-east-1
#   DEV_CLUSTER_NAME=claiset-dev
#   DEV_NODEGROUP_NAME=claiset-dev-default
#   DEV_NAMESPACE=dev
#   DEV_FRONTEND_HOST=claiset.xyz
#   DEV_RDS_ID=claiset-dev-postgres
#   DEV_NODE_MIN=1 DEV_NODE_DESIRED=1 DEV_NODE_MAX=2
#   DEV_SCALE_SCHEDULE=0   # set to 1 if you want schedule deployment running

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${DEV_CLUSTER_NAME:-claiset-dev}"
NODEGROUP="${DEV_NODEGROUP_NAME:-${CLUSTER}-default}"
NAMESPACE="${DEV_NAMESPACE:-dev}"
FRONTEND_HOST="${DEV_FRONTEND_HOST:-claiset.xyz}"
RDS_ID="${DEV_RDS_ID:-claiset-dev-postgres}"
NODE_MIN="${DEV_NODE_MIN:-1}"
NODE_DESIRED="${DEV_NODE_DESIRED:-1}"
NODE_MAX="${DEV_NODE_MAX:-2}"
SCALE_SCHEDULE="${DEV_SCALE_SCHEDULE:-0}"

echo "Resuming low-cost dev: cluster=${CLUSTER} namespace=${NAMESPACE} region=${REGION}"

echo "Step 1/5: Ensure nodegroup low-cost scaling (min=${NODE_MIN} desired=${NODE_DESIRED} max=${NODE_MAX})"
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

echo "Step 4/5: Scale core dev workloads"
kubectl -n "${NAMESPACE}" scale deployment web items outfits --replicas=1 >/dev/null
kubectl -n "${NAMESPACE}" scale deployment schedule --replicas="${SCALE_SCHEDULE}" >/dev/null

echo "Step 5/5: Reconcile Route53 alias from current Ingress"
pushd "${ROOT_DIR}/infra/envs/dev" >/dev/null
DOMAIN_ROOT=claiset.xyz FRONTEND_SUBDOMAIN= K8S_APP_NAMESPACE="${NAMESPACE}" bash ../../scripts/route53-ingress-records-guard.sh
popd >/dev/null

echo "Dev resume complete."
echo "Frontend: https://${FRONTEND_HOST}"
