#!/usr/bin/env bash
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after terraform init:
#   bash ../../scripts/terraform-eks-import-guard.sh
#
# If an EKS cluster/nodegroup already exists in AWS but isn't in Terraform state (common after
# cancelled applies or switching accounts), Terraform will fail trying to create duplicates.
# This guard imports the existing resources into state so apply can converge.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

if [[ -z "${EXPECTED_CLUSTER_NAME:-}" ]]; then
  echo "EXPECTED_CLUSTER_NAME is required (e.g. claiset-dev, claiset-qa)." >&2
  exit 1
fi

CLUSTER="${EXPECTED_CLUSTER_NAME}"
NODEGROUP="${EXPECTED_NODEGROUP_NAME:-${CLUSTER}-default}"

echo "EKS import guard: cluster=${CLUSTER} nodegroup=${NODEGROUP} region=${REGION}"

in_state() {
  local addr="$1"
  terraform state list 2>/dev/null | grep -qF -- "${addr}"
}

# Cluster
if aws eks describe-cluster --name "${CLUSTER}" --region "${REGION}" >/dev/null 2>&1; then
  if ! in_state "module.eks.aws_eks_cluster.this"; then
    echo "Importing existing EKS cluster into state"
    terraform import "module.eks.aws_eks_cluster.this" "${CLUSTER}"
  fi
fi

# Node group (cluster must exist in AWS for this call)
if aws eks describe-nodegroup --cluster-name "${CLUSTER}" --nodegroup-name "${NODEGROUP}" --region "${REGION}" >/dev/null 2>&1; then
  if ! in_state "module.eks.aws_eks_node_group.default"; then
    echo "Importing existing EKS node group into state"
    terraform import "module.eks.aws_eks_node_group.default" "${CLUSTER}:${NODEGROUP}"
  fi
fi

echo "EKS import guard OK."

