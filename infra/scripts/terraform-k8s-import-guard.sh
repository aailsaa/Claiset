#!/usr/bin/env bash
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after terraform init:
#   bash ../../scripts/terraform-k8s-import-guard.sh
#
# If a prior apply was cancelled, Kubernetes objects may exist in the cluster while Terraform
# state never recorded them. Subsequent applies then fail with "already exists".
# This guard imports existing app objects into state so apply can converge.

set -euo pipefail

NAMESPACE="${K8S_APP_NAMESPACE:-${TF_VAR_env:-dev}}"

in_state() {
  local addr="$1"
  terraform state show -no-color "${addr}" >/dev/null 2>&1
}

try_import() {
  local addr="$1" id="$2" desc="$3"

  if in_state "${addr}"; then
    return 0
  fi

  echo "Importing ${desc} ${id} into state"
  if terraform import "${addr}" "${id}"; then
    return 0
  fi

  # Common/expected when the object truly doesn't exist yet.
  echo "Skipping ${desc} ${id}: import failed (object may not exist yet)" >&2
  return 0
}

echo "K8s import guard: namespace=${NAMESPACE}"

# Backend must be usable. First-ever apply has no state file yet; that's OK.
STATE_LIST_ERR=""
if ! STATE_LIST_ERR="$(terraform state list 2>&1 >/dev/null)"; then
  if echo "${STATE_LIST_ERR}" | grep -qiE 'no state file was found|state snapshot was empty|cannot read state'; then
    echo "K8s import guard: no existing state yet (fresh env), continuing."
  else
    echo "::error::Unable to read Terraform state (unexpected error). Run terraform init in this directory (and ensure backend env vars are set in CI) before running this guard." >&2
    echo "${STATE_LIST_ERR}" >&2
    exit 1
  fi
fi

# Deployments
for name in items outfits schedule web; do
  addr="module.app_bluegreen.kubernetes_deployment.${name}[0]"
  try_import "${addr}" "${NAMESPACE}/${name}" "Deployment"
done

# Services
for name in items outfits schedule web; do
  addr="module.app_bluegreen.kubernetes_service.${name}[0]"
  try_import "${addr}" "${NAMESPACE}/${name}" "Service"
done

# Ingress (name is var.project; currently claiset)
INGRESS_NAME="${K8S_INGRESS_NAME:-${TF_VAR_project:-claiset}}"
addr_ing="module.app_bluegreen.kubernetes_ingress_v1.app[0]"
try_import "${addr_ing}" "${NAMESPACE}/${INGRESS_NAME}" "Ingress"

# Migrate Job
addr_job="module.app_bluegreen.kubernetes_job.migrate[0]"
try_import "${addr_job}" "${NAMESPACE}/migrate" "Job"

echo "K8s import guard OK."

