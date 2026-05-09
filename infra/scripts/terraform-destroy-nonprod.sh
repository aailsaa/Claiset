#!/usr/bin/env bash
# Destroy non-prod promotion environments (qa, uat) to cut recurring cost,
# while keeping dev and prod unchanged unless explicitly destroyed elsewhere.
#
# Usage (from repo root):
#   export TF_STATE_BUCKET=your-bootstrap-bucket
#   export TF_LOCK_TABLE=your-bootstrap-lock-table
#   export AWS_REGION=us-east-1   # or your region
#   ./infra/scripts/terraform-destroy-nonprod.sh
#
# Optional (recommended between short work sessions):
#   # Reduce EC2 spend while keeping dev cluster alive:
#   export PAUSE_DEV_NODES=1
#   ./infra/scripts/terraform-destroy-nonprod.sh
#
# Overrides for dev scale-down (defaults match this repo's naming):
#   export DEV_CLUSTER_NAME=claiset-dev
#   export DEV_NODEGROUP_NAME=claiset-dev-default
#
# This script is a thin wrapper around terraform-destroy-all.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
export TF_LOCK_TABLE="${TF_LOCK_TABLE:-}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "${TF_STATE_BUCKET}" || -z "${TF_LOCK_TABLE}" ]]; then
  echo "TF_STATE_BUCKET and TF_LOCK_TABLE must be set in the environment." >&2
  exit 1
fi

echo "Destroying non-prod environments (qa/uat) to eliminate major cost drivers while preserving prod."
"${ROOT_DIR}/infra/scripts/terraform-destroy-all.sh" qa uat

# Between short work sessions, keep dev but scale nodes down to reduce EC2 spend.
if [[ "${PAUSE_DEV_NODES:-0}" == "1" ]]; then
  DEV_CLUSTER_NAME="${DEV_CLUSTER_NAME:-claiset-dev}"
  DEV_NODEGROUP_NAME="${DEV_NODEGROUP_NAME:-${DEV_CLUSTER_NAME}-default}"
  echo
  echo "Scaling dev nodegroup down (keep dev up, reduce EC2 hours)."
  echo "cluster=${DEV_CLUSTER_NAME} nodegroup=${DEV_NODEGROUP_NAME} region=${AWS_REGION}"
  aws eks update-nodegroup-config \
    --region "${AWS_REGION}" \
    --cluster-name "${DEV_CLUSTER_NAME}" \
    --nodegroup-name "${DEV_NODEGROUP_NAME}" \
    --scaling-config "minSize=1,desiredSize=1,maxSize=6" >/dev/null
  aws eks wait nodegroup-active --region "${AWS_REGION}" --cluster-name "${DEV_CLUSTER_NAME}" --nodegroup-name "${DEV_NODEGROUP_NAME}"
  echo "Dev nodegroup scaled down."
fi


