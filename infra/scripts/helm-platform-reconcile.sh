#!/usr/bin/env bash
# Best-effort recovery for platform Helm releases before Terraform apply.
#
# Interrupted applies can leave releases in pending-install / failed / pending-upgrade /
# pending-rollback. The next apply then fails with "cannot re-use a name that is still in use".
# (Same class of issue as helm-monitoring-reconcile.sh, but for kube-system + platform charts.)
#
# Run from infra/envs/<env> after kubeconfig works (same point as k8s import guard).
# Only uninstalls a release when STATUS is a known stuck state; deployed/superseded are untouched.
#
# Usage:
#   export EXPECTED_CLUSTER_NAME=claiset-prod
#   export AWS_REGION=us-east-1
#   bash ../../scripts/helm-platform-reconcile.sh
#
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-}"

# namespace|release_name
PLATFORM_RELEASES=(
  "kube-system|aws-load-balancer-controller"
  "kube-system|cluster-autoscaler"
  "platform|external-dns"
)

die() {
  echo "helm-platform-reconcile: ${*}" >&2
  exit 1
}

ensure_helm() {
  if command -v helm >/dev/null 2>&1; then
    return 0
  fi
  echo "helm-platform-reconcile: helm not in PATH; bootstrapping Helm 3 to ${HOME}/.local/bin ..."
  mkdir -p "${HOME}/.local/bin"
  local os arch platform ver
  ver="${HELM_BOOTSTRAP_VERSION:-v3.14.4}"
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) echo "helm-platform-reconcile: unsupported OS ($(uname -s)), install helm CLI — skipping" >&2; return 1 ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=amd64 ;;
    *) echo "helm-platform-reconcile: unsupported CPU ($(uname -m)), skipping" >&2; return 1 ;;
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
  local ns="$2"
  helm status "${release}" -n "${ns}" 2>/dev/null | awk '/^STATUS:/{print tolower($2); exit}'
}

stuck_status() {
  case "$1" in
    pending-install | failed | pending-upgrade | pending-rollback) return 0 ;;
    *) return 1 ;;
  esac
}

maybe_uninstall() {
  local ns="$1"
  local release="$2"

  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    return 0
  fi

  local status
  status="$(helm_release_status "${release}" "${ns}" || true)"
  if [[ -z "${status}" ]]; then
    return 0
  fi
  if ! stuck_status "${status}"; then
    return 0
  fi

  echo "helm-platform-reconcile: uninstalling stuck release '${release}' in ${ns} (STATUS=${status})"
  helm uninstall "${release}" -n "${ns}" --wait --timeout=15m \
    || echo "helm-platform-reconcile: uninstall of ${release} returned non-zero; continuing anyway" >&2
}

if [[ -z "${CLUSTER}" ]]; then
  echo "helm-platform-reconcile: EXPECTED_CLUSTER_NAME unset — skipping." >&2
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "helm-platform-reconcile: aws CLI missing — skipping." >&2
  exit 0
fi

if ! aws eks describe-cluster --region "${REGION}" --name "${CLUSTER}" >/dev/null 2>&1; then
  echo "helm-platform-reconcile: cluster ${CLUSTER} not found — skipping." >&2
  exit 0
fi

if ! aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null 2>&1; then
  die "kubeconfig update failed"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "helm-platform-reconcile: kubectl missing — skipping." >&2
  exit 0
fi

if ! ensure_helm; then
  exit 0
fi

# Uninstall ALB controller before dependent charts if wedged (external-dns depends on it in Terraform).
for pair in "${PLATFORM_RELEASES[@]}"; do
  IFS='|' read -r ns rel <<<"${pair}"
  maybe_uninstall "${ns}" "${rel}"
done

echo "helm-platform-reconcile: OK (${CLUSTER})"
