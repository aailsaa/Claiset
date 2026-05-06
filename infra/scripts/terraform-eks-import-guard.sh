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
  terraform state show -no-color "${addr}" >/dev/null 2>&1
}

# Backend must be usable. First-ever apply has no state file yet; that's OK.
STATE_LIST_ERR=""
if ! STATE_LIST_ERR="$(terraform state list 2>&1 >/dev/null)"; then
  if echo "${STATE_LIST_ERR}" | grep -qiE 'no state file was found|state snapshot was empty|cannot read state'; then
    echo "EKS import guard: no existing state yet (fresh env), continuing."
  else
    echo "::error::Unable to read Terraform state (unexpected error). Run terraform init in this directory (and ensure backend env vars are set in CI) before running this guard." >&2
    echo "${STATE_LIST_ERR}" >&2
    exit 1
  fi
fi

try_import() {
  local addr="$1" id="$2" desc="$3"

  if in_state "${addr}"; then
    echo "${desc} already managed in state, skipping import"
    return 0
  fi

  echo "Importing existing ${desc} into state"
  if terraform import "${addr}" "${id}"; then
    return 0
  fi

  # If another step imported it first, treat as OK.
  echo "Skipping ${desc}: import failed (may already be managed)" >&2
  return 0
}

# Cluster
if aws eks describe-cluster --name "${CLUSTER}" --region "${REGION}" >/dev/null 2>&1; then
  try_import "module.eks.aws_eks_cluster.this" "${CLUSTER}" "EKS cluster"
fi

# Node group (cluster must exist in AWS for this call)
if aws eks describe-nodegroup --cluster-name "${CLUSTER}" --nodegroup-name "${NODEGROUP}" --region "${REGION}" >/dev/null 2>&1; then
  try_import "module.eks.aws_eks_node_group.default" "${CLUSTER}:${NODEGROUP}" "EKS node group"
fi

echo "EKS import guard OK."

