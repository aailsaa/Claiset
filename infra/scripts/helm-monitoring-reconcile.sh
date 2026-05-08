#!/usr/bin/env bash
# Best-effort recovery before Terraform installs observability Helm charts.
#
# Problem: interrupted applies leave releases in pending-install/failed → next apply hits
# "cannot re-use a name that is still in use". Terraform Helm does not auto-uninstall those.
# Also: **deployed** releases still in-cluster but missing from Terraform state → import (same as helm-platform-reconcile).
#
# Run from infra/envs/<env> AFTER cluster exists, kube-credentials work, and `terraform init` (same as k8s import guard).
# Uninstall only when STATUS is stuck; healthy **deployed** releases are imported into state, not deleted.
#
# Usage:
#   export EXPECTED_CLUSTER_NAME=claiset-dev   # required
#   export AWS_REGION=us-east-1
#   bash ../../scripts/helm-monitoring-reconcile.sh
#
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-}"
MON_NS="${HELM_MON_NAMESPACE:-monitoring}"

# Releases Terraform manages for observability (order: prometheus stack must not be arbitrarily removed ahead of dependents;
# uninstall order is handled bottom-up in the loops below.)
STACK_RELS=(
  promtail
  loki
  kube-prometheus-stack
)

die() {
  echo "helm-monitoring-reconcile: ${*}" >&2
  exit 1
}

ensure_helm() {
  if command -v helm >/dev/null 2>&1; then
    return 0
  fi
  echo "helm-monitoring-reconcile: helm not in PATH; bootstrapping Helm 3 to ${HOME}/.local/bin ..."
  mkdir -p "${HOME}/.local/bin"
  local os arch platform ver
  ver="${HELM_BOOTSTRAP_VERSION:-v3.14.4}"
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) echo "helm-monitoring-reconcile: unsupported OS ($(uname -s)), install helm CLI — skipping" >&2; return 1 ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=amd64 ;;
    *) echo "helm-monitoring-reconcile: unsupported CPU ($(uname -m)), skipping" >&2; return 1 ;;
  esac
  platform="${os}-${arch}"
  local tarball url
  url="https://get.helm.sh/helm-${ver}-${platform}.tar.gz"
  tarball="$(mktemp)"
  curl -fsSL "${url}" -o "${tarball}"
  tar -xzf "${tarball}" -C "$(dirname "${tarball}")" "${platform}/helm"
  mv "$(dirname "${tarball}")/${platform}/helm" "${HOME}/.local/bin/helm"
  rm -f "${tarball}"
  chmod +x "${HOME}/.local/bin/helm"
  export PATH="${HOME}/.local/bin:${PATH}"
}

helm_release_status() {
  local release="$1"
  # Plain-text `helm status` includes a line like: STATUS: pending-install
  helm status "${release}" -n "${MON_NS}" 2>/dev/null | awk '/^STATUS:/{print tolower($2); exit}'
}

maybe_uninstall() {
  local release="$1"
  local status
  status="$(helm_release_status "${release}" || true)"
  if [[ "${status}" == "" ]]; then
    return 0
  fi
  if [[ "${status}" != "pending-install" && "${status}" != "failed" && "${status}" != "pending-upgrade" && "${status}" != "pending-rollback" ]]; then
    return 0
  fi

  echo "helm-monitoring-reconcile: uninstalling stuck release '${release}' in ${MON_NS} (STATUS=${status})"
  helm uninstall "${release}" -n "${MON_NS}" --wait --timeout=15m \
    || echo "helm-monitoring-reconcile: uninstall of ${release} returned non-zero; continuing anyway" >&2
}

maybe_import_deployed() {
  local tf_addr="$1"
  local ns="$2"
  local helm_name="$3"

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  if ! terraform state list >/dev/null 2>&1; then
    echo "helm-monitoring-reconcile: terraform not initialized in $(pwd); skipping import for ${tf_addr}" >&2
    return 0
  fi
  if terraform state show -no-color "${tf_addr}" >/dev/null 2>&1; then
    return 0
  fi

  # pipefail + missing release => helm exits 1; must not kill this script before Phase 2 apply.
  local status
  status="$(helm status "${helm_name}" -n "${ns}" 2>/dev/null | awk '/^STATUS:/{print tolower($2); exit}')" || true
  if [[ "${status}" != "deployed" ]]; then
    return 0
  fi

  local import_id="${ns}/${helm_name}"
  echo "helm-monitoring-reconcile: importing deployed release into Terraform state: ${tf_addr} <- ${import_id}"
  set +e
  terraform import "${tf_addr}" "${import_id}"
  local rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    echo "helm-monitoring-reconcile: terraform import ${tf_addr} failed (exit ${rc}); often OK if observability is off in this workspace" >&2
  fi
  return 0
}

if [[ -z "${CLUSTER}" ]]; then
  echo "helm-monitoring-reconcile: EXPECTED_CLUSTER_NAME unset — skipping." >&2
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "helm-monitoring-reconcile: aws CLI missing — skipping." >&2
  exit 0
fi

if ! aws eks describe-cluster --region "${REGION}" --name "${CLUSTER}" >/dev/null 2>&1; then
  echo "helm-monitoring-reconcile: cluster ${CLUSTER} not found — skipping." >&2
  exit 0
fi

if ! aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null 2>&1; then
  die "kubeconfig update failed"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "helm-monitoring-reconcile: kubectl missing — skipping." >&2
  exit 0
fi

if ! kubectl get ns "${MON_NS}" >/dev/null 2>&1; then
  echo "helm-monitoring-reconcile: namespace '${MON_NS}' does not exist yet — skipping." >&2
  exit 0
fi

if ! ensure_helm; then
  exit 0
fi

# Uninstall dependents first when stack is wedged so CRDs/subcharts do not deadlock.
for rel in "${STACK_RELS[@]}"; do
  maybe_uninstall "${rel}"
done

# Adopt healthy releases missing from state (stack order: prometheus → loki → promtail).
maybe_import_deployed "module.platform.helm_release.kube_prometheus_stack[0]" "${MON_NS}" "kube-prometheus-stack"
maybe_import_deployed "module.platform.helm_release.loki[0]" "${MON_NS}" "loki"
maybe_import_deployed "module.platform.helm_release.promtail[0]" "${MON_NS}" "promtail"

echo "helm-monitoring-reconcile: OK (${CLUSTER}/${MON_NS})"
