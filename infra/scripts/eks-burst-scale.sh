#!/usr/bin/env bash
# Temporarily adjust an EKS managed nodegroup scaling config.
#
# Usage:
#   AWS_REGION=us-east-1 ./infra/scripts/eks-burst-scale.sh <cluster> <nodegroup> <min> <desired> <max>
#
# Intended for CI to "burst" capacity during app rollout, then scale down after.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <cluster> <nodegroup> <min> <desired> <max>" >&2
  exit 2
fi

CLUSTER="$1"
NODEGROUP="$2"
MIN="$3"
DESIRED="$4"
MAX="$5"

echo "Scaling nodegroup: cluster=${CLUSTER} nodegroup=${NODEGROUP} region=${REGION} min=${MIN} desired=${DESIRED} max=${MAX}"

aws eks update-nodegroup-config \
  --region "${REGION}" \
  --cluster-name "${CLUSTER}" \
  --nodegroup-name "${NODEGROUP}" \
  --scaling-config "minSize=${MIN},desiredSize=${DESIRED},maxSize=${MAX}" >/dev/null

# Wait until the nodegroup reports Active again (doesn't guarantee nodes are Ready, but is a good signal).
aws eks wait nodegroup-active --region "${REGION}" --cluster-name "${CLUSTER}" --nodegroup-name "${NODEGROUP}"

echo "Nodegroup scaling update applied."

