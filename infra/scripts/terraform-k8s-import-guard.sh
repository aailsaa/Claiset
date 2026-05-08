#!/usr/bin/env bash
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after terraform init:
#   bash ../../scripts/terraform-k8s-import-guard.sh
#
# If a prior apply was cancelled, Kubernetes objects may exist in the cluster while Terraform
# state never recorded them. Subsequent applies then fail with "already exists".
# This guard imports existing app objects, platform namespaces, and observability secrets
# into state so apply can converge.

set -euo pipefail

NAMESPACE="${K8S_APP_NAMESPACE:-${TF_VAR_env:-dev}}"

in_state() {
  local addr="$1"
  terraform state show -no-color "${addr}" >/dev/null 2>&1
}

# Optional 4th arg: pre-check with kubectl so we do not call terraform import when the object
# is missing (avoids noisy "Cannot import non-existent remote object" on first deploy).
try_import() {
  local addr="$1" id="$2" desc="$3"
  local check="${4:-}"

  if in_state "${addr}"; then
    return 0
  fi

  if [[ -n "${check}" ]]; then
    case "${check}" in
      ns)
        if ! kubectl get ns "${id}" >/dev/null 2>&1; then
          echo "K8s import guard: skip ${desc} (namespace ${id} not in cluster)"
          return 0
        fi
        ;;
      secret)
        local sns="${id%%/*}" sname="${id#*/}"
        if ! kubectl get secret -n "${sns}" "${sname}" >/dev/null 2>&1; then
          echo "K8s import guard: skip ${desc} (secret not in cluster)"
          return 0
        fi
        ;;
      deployment|svc|ingress)
        local kns="${id%%/*}" kres="${id#*/}"
        if ! kubectl get "${check}" -n "${kns}" "${kres}" >/dev/null 2>&1; then
          echo "K8s import guard: skip ${desc} (${check} ${kns}/${kres} not in cluster)"
          return 0
        fi
        ;;
      job)
        local kns="${id%%/*}" kres="${id#*/}"
        if ! kubectl get job.batch -n "${kns}" "${kres}" >/dev/null 2>&1 \
          && ! kubectl get job -n "${kns}" "${kres}" >/dev/null 2>&1; then
          echo "K8s import guard: skip ${desc} (job ${kns}/${kres} not in cluster)"
          return 0
        fi
        ;;
    esac
  fi

  echo "Importing ${desc} ${id} into state"
  if terraform import "${addr}" "${id}"; then
    return 0
  fi

  echo "Skipping ${desc} ${id}: import failed (unexpected)" >&2
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

# Platform module namespaces (partial applies can create these without state).
try_import "module.platform.kubernetes_namespace.platform" "platform" "Namespace" ns
# Observability namespace — only in config when observability_enabled (OAuth + flags) matches CI; else import no-ops.
try_import "module.platform.kubernetes_namespace.monitoring[0]" "monitoring" "Namespace" ns
# Grafana OAuth secret (same observability_enabled gate as namespace).
try_import "module.platform.kubernetes_secret.grafana_google_oauth[0]" "monitoring/grafana-google-oauth" "Secret" secret

# Deployments
for name in items outfits schedule web; do
  addr="module.app_bluegreen.kubernetes_deployment.${name}[0]"
  try_import "${addr}" "${NAMESPACE}/${name}" "Deployment" deployment
done

# Services
for name in items outfits schedule web; do
  addr="module.app_bluegreen.kubernetes_service.${name}[0]"
  try_import "${addr}" "${NAMESPACE}/${name}" "Service" svc
done

# Ingress (name is var.project; currently claiset)
INGRESS_NAME="${K8S_INGRESS_NAME:-${TF_VAR_project:-claiset}}"
addr_ing="module.app_bluegreen.kubernetes_ingress_v1.app[0]"
try_import "${addr_ing}" "${NAMESPACE}/${INGRESS_NAME}" "Ingress" ingress

# Migrate Job — often absent after a successful run (manual cleanup, TTL policies) while state
# still references it; apply then fails refreshing this address. Drop stale state so apply recreates.
addr_job="module.app_bluegreen.kubernetes_job.migrate[0]"
job_present() {
  kubectl get job.batch -n "${NAMESPACE}" migrate >/dev/null 2>&1 \
    || kubectl get job -n "${NAMESPACE}" migrate >/dev/null 2>&1
}
if in_state "${addr_job}" && ! job_present; then
  echo "K8s import guard: migrate job in Terraform state but not in cluster; removing from state so apply recreates it"
  terraform state rm "${addr_job}" \
    || echo "K8s import guard: warning: terraform state rm failed for ${addr_job}; if apply errors on migrate, run: terraform state rm '${addr_job}'" >&2
fi
try_import "${addr_job}" "${NAMESPACE}/migrate" "Job" job

echo "K8s import guard OK."

