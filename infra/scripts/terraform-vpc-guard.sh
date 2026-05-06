#!/usr/bin/env bash
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after terraform init:
#   bash ../../scripts/terraform-vpc-guard.sh
#
# Prevents duplicate VPCs: fails if more than one VPC is tagged Name=<project>-<env>, or if such a
# VPC exists in AWS while Terraform state does not track module.network (would create a second VPC).

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

# CI should set EXPECTED_VPC_NAME (matches module.network Name tag: var.project-var.env).
# Avoids `terraform console`, which can take minutes loading providers/backend.
if [[ -n "${EXPECTED_VPC_NAME:-}" ]]; then
  VPC_NAME="${EXPECTED_VPC_NAME}"
elif ! VPC_NAME="$(echo 'format("%s-%s", var.project, var.env)' | terraform console 2>/dev/null | sed 's/^"//;s/"$//' | tr -d '\r')"; then
  echo "terraform console failed; run terraform init in this directory first, or set EXPECTED_VPC_NAME." >&2
  exit 1
fi

if [[ -z "${VPC_NAME}" ]]; then
  echo "Could not resolve VPC name (set EXPECTED_VPC_NAME or fix var.project / var.env)." >&2
  exit 1
fi

echo "VPC guard: Name tag=${VPC_NAME} region=${REGION}"

# Ensure Terraform backend is usable. On first-ever apply there may be no state file yet; that's OK.
STATE_LIST_ERR=""
if ! STATE_LIST_ERR="$(terraform state list 2>&1 >/dev/null)"; then
  if echo "${STATE_LIST_ERR}" | grep -qiE 'no state file was found|state snapshot was empty|cannot read state'; then
    echo "VPC guard: no existing state yet (fresh env), continuing."
  else
    echo "::error::Unable to read Terraform state (unexpected error). Run terraform init in this directory (and ensure backend env vars are set in CI) before running this guard." >&2
    echo "${STATE_LIST_ERR}" >&2
    exit 1
  fi
fi

COUNT="$(aws ec2 describe-vpcs --region "${REGION}" \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'length(Vpcs)' --output text)"

if [[ ! "${COUNT}" =~ ^[0-9]+$ ]]; then
  echo "Unexpected AWS CLI output for VPC count: ${COUNT}" >&2
  exit 1
fi

if [[ "${COUNT}" -gt 1 ]]; then
  echo "::error::Found ${COUNT} VPCs tagged Name=${VPC_NAME}. Delete orphan VPCs (keep the one used by EKS/RDS) before apply." >&2
  aws ec2 describe-vpcs --region "${REGION}" \
    --filters "Name=tag:Name,Values=${VPC_NAME}" \
    --query 'Vpcs[*].[VpcId,CidrBlock]' --output table >&2
  exit 1
fi

VPC_IN_STATE=0
if terraform state show -no-color 'module.network.module.vpc.aws_vpc.this[0]' >/dev/null 2>&1; then
  VPC_IN_STATE=1
fi

if [[ "${COUNT}" -ge 1 && "${VPC_IN_STATE}" -eq 0 ]]; then
  echo "::error::A VPC tagged Name=${VPC_NAME} exists in AWS, but Terraform state has no module.network VPC resource." >&2
  echo "Restore backend state or import the existing VPC before apply; otherwise Terraform will create another VPC." >&2
  aws ec2 describe-vpcs --region "${REGION}" \
    --filters "Name=tag:Name,Values=${VPC_NAME}" \
    --query 'Vpcs[*].VpcId' --output text >&2
  exit 1
fi

echo "VPC guard OK (matching VPCs in AWS: ${COUNT}; tracked in state: ${VPC_IN_STATE})."
