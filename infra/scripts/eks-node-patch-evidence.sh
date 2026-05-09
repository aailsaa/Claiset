#!/usr/bin/env bash
# Prints a timestamped snapshot of EKS managed nodegroup + Kubernetes nodes — use for
# OS/patching rubric BEFORE/AFTER captures (paste or redirect to docs/evidence-media/*.txt).
#
# Usage:
#   bash infra/scripts/eks-node-patch-evidence.sh [cluster_name] [nodegroup_name]
# Defaults: CLUSTER from env CLUSTER or claiset-dev; NODEGROUP from env NODEGROUP or ${CLUSTER}-default
#
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${1:-${CLUSTER:-claiset-dev}}"
NODEGROUP="${2:-${NODEGROUP:-${CLUSTER}-default}}"

echo "=============================================="
echo "EKS node patch evidence snapshot UTC $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "CLUSTER=${CLUSTER} NODEGROUP=${NODEGROUP} REGION=${REGION}"
echo "=============================================="

if command -v aws >/dev/null 2>&1; then
  echo ""
  echo "--- aws eks describe-nodegroup (subset) ---"
  aws eks describe-nodegroup \
    --region "${REGION}" \
    --cluster-name "${CLUSTER}" \
    --nodegroup-name "${NODEGROUP}" \
    --query 'nodegroup.{Status:status,CapacityType:capacityType,K8sVersion:version,ReleaseVersion:releaseVersion,InstanceTypes:instanceTypes,Scaling:scalingConfig,UpdateCfg:updateConfig}' \
    --output yaml 2>&1 || echo "(aws describe-nodegroup failed — check CLUSTER/NODEGROUP/region/credentials)"
fi

echo ""
echo "--- kubectl get nodes -o wide ---"
kubectl get nodes -o wide 2>&1 || echo "(kubectl failed — run aws eks update-kubeconfig for ${CLUSTER})"

echo ""
echo "=============================================="
