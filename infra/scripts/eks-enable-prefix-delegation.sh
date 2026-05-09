#!/usr/bin/env bash
# Enable AWS VPC CNI prefix delegation to raise pod density per node.
# This is critical on small instance types where default ENI/IP limits can
# cause repeated "Too many pods" scheduling failures.
#
# Usage:
#   AWS_REGION=us-east-1 EXPECTED_CLUSTER_NAME=claiset-prod \
#   bash ../../scripts/eks-enable-prefix-delegation.sh

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-}"

if [[ -z "${CLUSTER}" ]]; then
  echo "eks-enable-prefix-delegation: EXPECTED_CLUSTER_NAME is required." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
  echo "eks-enable-prefix-delegation: aws and kubectl are required." >&2
  exit 1
fi

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

if ! kubectl -n kube-system get ds aws-node >/dev/null 2>&1; then
  echo "eks-enable-prefix-delegation: aws-node daemonset not found; skipping." >&2
  exit 0
fi

echo "eks-enable-prefix-delegation: enabling prefix delegation on ${CLUSTER}"
kubectl -n kube-system set env ds/aws-node \
  ENABLE_PREFIX_DELEGATION=true \
  WARM_PREFIX_TARGET=1 \
  WARM_IP_TARGET=0 >/dev/null

echo "eks-enable-prefix-delegation: waiting for aws-node rollout"
kubectl -n kube-system rollout status ds/aws-node --timeout=15m

echo "eks-enable-prefix-delegation: current node pod capacities"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" pods="}{.status.capacity.pods}{"\n"}{end}' || true
