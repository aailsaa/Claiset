#!/usr/bin/env bash
# Best-effort recovery for platform Helm releases before Terraform apply.
#
# Interrupted applies can leave releases in pending-install / failed / pending-upgrade /
# pending-rollback. The next apply then fails with "cannot re-use a name that is still in use".
# (Same class of issue as helm-monitoring-reconcile.sh, but for kube-system + platform charts.)
#
# Also fixes drift: a **deployed** release still in the cluster but **missing from Terraform state**
# (partial apply, lock/cancel mid-write) — Terraform would try to "create" and Helm rejects the name.
# In that case we run `terraform import` when cwd is an initialized env dir.
#
# Run from infra/envs/<env> after kubeconfig works and `terraform init` (same point as k8s import guard).
# Only uninstalls a release when STATUS is a known stuck state; healthy deployed releases are imported, not deleted.
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

# Adopt an existing healthy Helm release into state so Terraform does not try to create it again.
maybe_import_deployed() {
  local tf_addr="$1"
  local ns="$2"
  local helm_name="$3"

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  if ! terraform state list >/dev/null 2>&1; then
    echo "helm-platform-reconcile: terraform not initialized in $(pwd); skipping state drift import for ${tf_addr}" >&2
    return 0
  fi
  if terraform state show -no-color "${tf_addr}" >/dev/null 2>&1; then
    return 0
  fi
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    return 0
  fi

  local status
  status="$(helm_release_status "${helm_name}" "${ns}" || true)"
  if [[ "${status}" != "deployed" ]]; then
    return 0
  fi

  local import_id="${ns}/${helm_name}"
  echo "helm-platform-reconcile: importing deployed release into Terraform state: ${tf_addr} <- ${import_id}"
  set +e
  terraform import "${tf_addr}" "${import_id}"
  local rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    echo "helm-platform-reconcile: terraform import ${tf_addr} failed (exit ${rc}); often OK if this chart is not in this workspace (e.g. external-dns without domain)" >&2
  fi
  return 0
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

# Adopt healthy releases that exist in-cluster but not in state (fixes "cannot re-use a name" on create).
maybe_import_deployed "module.platform.helm_release.aws_load_balancer_controller" "kube-system" "aws-load-balancer-controller"
maybe_import_deployed "module.platform.helm_release.cluster_autoscaler[0]" "kube-system" "cluster-autoscaler"
maybe_import_deployed "module.platform.helm_release.external_dns[0]" "platform" "external-dns"

echo "helm-platform-reconcile: OK (${CLUSTER})"
