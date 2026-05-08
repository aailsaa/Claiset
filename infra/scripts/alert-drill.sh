#!/usr/bin/env bash
# Intentionally trigger and revert a Prometheus/Alertmanager readiness alert.
#
# Default behavior targets one backend deployment and scales it to 0 replicas
# long enough to fire `ClaisetBackendPodNotReady` (for=10m), then restores it.
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
# - `trigger` stores current replicas as a deployment annotation.
# - `revert` restores from that annotation (falls back to 1 if missing).

set -euo pipefail

MODE="${1:-status}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-claiset-dev}"
NAMESPACE="${K8S_APP_NAMESPACE:-dev}"
DEPLOYMENT="${ALERT_TARGET_DEPLOYMENT:-items}"
ORIG_REPLICAS_ANNOTATION="claiset.xyz/alert-drill-original-replicas"

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

current_replicas() {
  kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath='{.spec.replicas}'
}

saved_replicas() {
  kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath="{.metadata.annotations.${ORIG_REPLICAS_ANNOTATION//\//\\.}}" 2>/dev/null || true
}

print_status() {
  local replicas
  local ready
  local saved
  replicas="$(current_replicas)"
  ready="$(kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  saved="$(saved_replicas)"
  echo "Cluster=${CLUSTER} Namespace=${NAMESPACE} Deployment=${DEPLOYMENT}"
  echo "Replicas spec=${replicas} ready=${ready:-0} saved_original=${saved:-<none>}"
}

trigger_alert() {
  local orig
  orig="$(current_replicas)"
  if [[ -z "${orig}" ]]; then
    echo "Could not read current replicas for ${NAMESPACE}/${DEPLOYMENT}" >&2
    exit 1
  fi

  kubectl -n "${NAMESPACE}" annotate deployment "${DEPLOYMENT}" \
    "${ORIG_REPLICAS_ANNOTATION}=${orig}" --overwrite >/dev/null
  kubectl -n "${NAMESPACE}" scale deployment "${DEPLOYMENT}" --replicas=0 >/dev/null

  echo "Triggered alert drill: scaled ${NAMESPACE}/${DEPLOYMENT} from ${orig} -> 0"
  echo "Leave this for at least 10 minutes to satisfy alert rule 'for: 10m'."
  echo "Run: ./infra/scripts/alert-drill.sh revert"
}

revert_alert() {
  local restore_to
  restore_to="$(saved_replicas)"
  if [[ -z "${restore_to}" ]]; then
    restore_to="1"
  fi

  kubectl -n "${NAMESPACE}" scale deployment "${DEPLOYMENT}" --replicas="${restore_to}" >/dev/null
  kubectl -n "${NAMESPACE}" annotate deployment "${DEPLOYMENT}" "${ORIG_REPLICAS_ANNOTATION}-" >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=6m

  echo "Reverted alert drill: restored ${NAMESPACE}/${DEPLOYMENT} replicas to ${restore_to}"
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
