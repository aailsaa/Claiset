#!/usr/bin/env bash
# Intentionally trigger and revert a Prometheus/Alertmanager readiness alert.
#
# Fires `ClaisetBackendPodNotReady` (for=10m) by making the target deployment's
# readiness probe hit a non-existent HTTP path while keeping spec.replicas >= 1.
# Scaling to 0 alone often does NOT fire that alert: kube-state-metrics may emit
# no `kube_pod_status_ready{condition="false"}` series once pods are gone, so the
# PromQL never stays > 0 for 10 minutes.
#
# Usage (from repo root):
#   ./infra/scripts/alert-drill.sh trigger
#   ./infra/scripts/alert-drill.sh status
#   ./infra/scripts/alert-drill.sh revert
#
# Optional overrides:
#   AWS_REGION=us-east-1
#   EXPECTED_CLUSTER_NAME=claiset-dev
#   K8S_APP_NAMESPACE=dev
#   ALERT_TARGET_DEPLOYMENT=items
#
# Notes:
# - `trigger` stores original readiness path + replica count on the Deployment.
# - `revert` restores probe path and replica count from annotations.

set -euo pipefail

MODE="${1:-status}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-claiset-dev}"
NAMESPACE="${K8S_APP_NAMESPACE:-dev}"
DEPLOYMENT="${ALERT_TARGET_DEPLOYMENT:-items}"
ORIG_REPLICAS_ANNOTATION="claiset.xyz/alert-drill-original-replicas"
ORIG_PATH_ANNOTATION="claiset.xyz/alert-drill-original-readiness-path"
DRILL_ACTIVE_ANNOTATION="claiset.xyz/alert-drill-active"
FAIL_PATH="/__claiset_alert_drill__/not-found"

require_mode() {
  case "${MODE}" in
    trigger|revert|status) ;;
    *)
      echo "Unknown mode: ${MODE}" >&2
      echo "Use one of: trigger | revert | status" >&2
      exit 1
      ;;
  esac
}

ensure_target_exists() {
  if ! kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" >/dev/null 2>&1; then
    echo "Deployment ${NAMESPACE}/${DEPLOYMENT} not found." >&2
    exit 1
  fi
}

container_index_for_deployment() {
  # items/outfits/schedule: single container named same as deployment (Terraform).
  local idx
  idx="$(kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); c=d["spec"]["template"]["spec"]["containers"]; name=sys.argv[1]; print(next(i for i,x in enumerate(c) if x["name"]==name))' "${DEPLOYMENT}" 2>/dev/null || true)"
  if [[ -z "${idx}" ]]; then
    echo "Could not find container named ${DEPLOYMENT} in ${NAMESPACE}/${DEPLOYMENT}." >&2
    exit 1
  fi
  echo "${idx}"
}

readiness_http_path() {
  local idx="$1"
  kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath="{.spec.template.spec.containers[${idx}].readinessProbe.httpGet.path}" 2>/dev/null || true
}

current_replicas() {
  kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath='{.spec.replicas}'
}

saved_replicas() {
  kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath="{.metadata.annotations.${ORIG_REPLICAS_ANNOTATION//\//\\.}}" 2>/dev/null || true
}

saved_path() {
  kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath="{.metadata.annotations.${ORIG_PATH_ANNOTATION//\//\\.}}" 2>/dev/null || true
}

print_status() {
  local replicas
  local ready
  local saved_rep
  local saved_p
  local idx
  local path_now
  replicas="$(current_replicas)"
  ready="$(kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  saved_rep="$(saved_replicas)"
  saved_p="$(saved_path)"
  idx="$(container_index_for_deployment)"
  path_now="$(readiness_http_path "${idx}")"
  echo "Cluster=${CLUSTER} Namespace=${NAMESPACE} Deployment=${DEPLOYMENT}"
  echo "Replicas spec=${replicas} ready=${ready:-0} saved_original_replicas=${saved_rep:-<none>}"
  echo "readinessProbe.httpGet.path now=${path_now:-<none>} saved_original_path=${saved_p:-<none>}"
}

patch_readiness_path() {
  local idx="$1"
  local new_path="$2"
  kubectl -n "${NAMESPACE}" patch deployment "${DEPLOYMENT}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/${idx}/readinessProbe/httpGet/path\",\"value\":\"${new_path}\"}]" >/dev/null
}

trigger_alert() {
  local idx
  local orig_rep
  local orig_path

  if [[ "$(kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath="{.metadata.annotations.${DRILL_ACTIVE_ANNOTATION//\//\\.}}" 2>/dev/null || true)" == "1" ]]; then
    echo "Drill already active on ${NAMESPACE}/${DEPLOYMENT} (${DRILL_ACTIVE_ANNOTATION}=1). Run revert first." >&2
    exit 1
  fi

  idx="$(container_index_for_deployment)"
  orig_rep="$(current_replicas)"
  if [[ -z "${orig_rep}" ]]; then
    echo "Could not read current replicas for ${NAMESPACE}/${DEPLOYMENT}" >&2
    exit 1
  fi

  orig_path="$(readiness_http_path "${idx}")"
  if [[ -z "${orig_path}" ]]; then
    echo "No httpGet readiness probe path found on ${NAMESPACE}/${DEPLOYMENT} container index ${idx}; cannot drill." >&2
    exit 1
  fi

  kubectl -n "${NAMESPACE}" annotate deployment "${DEPLOYMENT}" \
    "${ORIG_REPLICAS_ANNOTATION}=${orig_rep}" \
    "${ORIG_PATH_ANNOTATION}=${orig_path}" \
    "${DRILL_ACTIVE_ANNOTATION}=1" --overwrite >/dev/null

  if [[ "${orig_rep}" -eq 0 ]]; then
    echo "Deployment had 0 replicas; scaling to 1 so pods exist for the readiness alert metric."
    kubectl -n "${NAMESPACE}" scale deployment "${DEPLOYMENT}" --replicas=1 >/dev/null
    kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=6m
  fi

  patch_readiness_path "${idx}" "${FAIL_PATH}"

  echo "Triggered alert drill: readiness path ${orig_path} -> ${FAIL_PATH} (replicas unchanged except 0->1 if needed)."
  echo "Leave running for at least 10 minutes to satisfy alert rule 'for: 10m' (ClaisetBackendPodNotReady)."
  echo "Then run: ./infra/scripts/alert-drill.sh revert"
}

revert_alert() {
  local idx
  local restore_rep
  local restore_path

  idx="$(container_index_for_deployment)"
  restore_rep="$(saved_replicas)"
  restore_path="$(saved_path)"

  if [[ -z "${restore_path}" ]]; then
    restore_path="/health"
  fi
  if [[ -z "${restore_rep}" ]]; then
    restore_rep="1"
  fi

  patch_readiness_path "${idx}" "${restore_path}"
  kubectl -n "${NAMESPACE}" scale deployment "${DEPLOYMENT}" --replicas="${restore_rep}" >/dev/null
  kubectl -n "${NAMESPACE}" annotate deployment "${DEPLOYMENT}" \
    "${ORIG_REPLICAS_ANNOTATION}-" \
    "${ORIG_PATH_ANNOTATION}-" \
    "${DRILL_ACTIVE_ANNOTATION}-" >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=6m

  echo "Reverted alert drill: restored readiness path to ${restore_path}, replicas to ${restore_rep}"
}

main() {
  require_mode
  aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null
  ensure_target_exists

  case "${MODE}" in
    trigger) trigger_alert ;;
    revert) revert_alert ;;
    status) print_status ;;
  esac
}

main
