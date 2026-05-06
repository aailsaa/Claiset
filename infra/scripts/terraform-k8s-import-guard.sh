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
  terraform state list 2>/dev/null | grep -qF -- "${addr}"
}

has_deploy() { kubectl -n "${NAMESPACE}" get deploy "$1" >/dev/null 2>&1; }
has_svc() { kubectl -n "${NAMESPACE}" get svc "$1" >/dev/null 2>&1; }
has_job() { kubectl -n "${NAMESPACE}" get job "$1" >/dev/null 2>&1; }
has_ing() { kubectl -n "${NAMESPACE}" get ingress "$1" >/dev/null 2>&1; }

echo "K8s import guard: namespace=${NAMESPACE}"

# Deployments
for name in items outfits schedule web; do
  addr="module.app_bluegreen.kubernetes_deployment.${name}[0]"
  if has_deploy "${name}" && ! in_state "${addr}"; then
    echo "Importing Deployment ${NAMESPACE}/${name} into state"
    terraform import "${addr}" "${NAMESPACE}/${name}"
  fi
done

# Services
for name in items outfits schedule web; do
  addr="module.app_bluegreen.kubernetes_service.${name}[0]"
  if has_svc "${name}" && ! in_state "${addr}"; then
    echo "Importing Service ${NAMESPACE}/${name} into state"
    terraform import "${addr}" "${NAMESPACE}/${name}"
  fi
done

# Ingress (name is var.project; currently claiset)
INGRESS_NAME="${K8S_INGRESS_NAME:-${TF_VAR_project:-claiset}}"
addr_ing="module.app_bluegreen.kubernetes_ingress_v1.app[0]"
if has_ing "${INGRESS_NAME}" && ! in_state "${addr_ing}"; then
  echo "Importing Ingress ${NAMESPACE}/${INGRESS_NAME} into state"
  terraform import "${addr_ing}" "${NAMESPACE}/${INGRESS_NAME}"
fi

# Migrate Job
addr_job="module.app_bluegreen.kubernetes_job.migrate[0]"
if has_job "migrate" && ! in_state "${addr_job}"; then
  echo "Importing Job ${NAMESPACE}/migrate into state"
  terraform import "${addr_job}" "${NAMESPACE}/migrate"
fi

echo "K8s import guard OK."

