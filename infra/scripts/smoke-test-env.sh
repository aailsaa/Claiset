#!/usr/bin/env bash
# Quick post-deploy smoke test for an environment.
# Checks:
# 1) core app Deployments are Ready
# 2) Ingress has a load balancer address
# 3) frontend URL responds (2xx/3xx)
# 4) backend API routes do not return 5xx
# 5) RDS instance for this env is Available
#
# Usage (run from infra/envs/<env> after apply):
#   EXPECTED_CLUSTER_NAME=claiset-dev K8S_APP_NAMESPACE=dev FRONTEND_HOST=claiset.xyz \
#   bash ../../scripts/smoke-test-env.sh

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-}"
NAMESPACE="${K8S_APP_NAMESPACE:-${TF_VAR_env:-dev}}"
PROJECT="${TF_VAR_project:-claiset}"
FRONTEND_HOST="${FRONTEND_HOST:-}"
RDS_ID="${RDS_INSTANCE_ID:-${PROJECT}-${NAMESPACE}-postgres}"

if [[ -z "${CLUSTER}" ]]; then
  echo "EXPECTED_CLUSTER_NAME is required." >&2
  exit 1
fi

if [[ -z "${FRONTEND_HOST}" ]]; then
  echo "FRONTEND_HOST is required (e.g. claiset.xyz, app-qa.claiset.xyz)." >&2
  exit 1
fi

echo "Smoke test: cluster=${CLUSTER} namespace=${NAMESPACE} frontend=${FRONTEND_HOST} region=${REGION}"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

for d in web items outfits schedule; do
  echo "Checking rollout: deployment/${d} in ${NAMESPACE}"
  kubectl -n "${NAMESPACE}" rollout status "deployment/${d}" --timeout=8m
done

wait_for_no_pending_app_pods() {
  local attempts=36
  local sleep_s=5
  local i pending
  echo "Waiting for app pods to leave Pending state..."
  for ((i=1; i<=attempts; i++)); do
    pending="$(kubectl -n "${NAMESPACE}" get pods -l 'app in (web,items,outfits,schedule)' --no-headers 2>/dev/null | awk '$3=="Pending"{c++} END{print c+0}')"
    if [[ "${pending}" == "0" ]]; then
      echo "No Pending app pods."
      return 0
    fi
    echo "Pending app pods: ${pending} (attempt ${i}/${attempts})"
    sleep "${sleep_s}"
  done
  echo "App pods remained Pending too long; failing smoke test." >&2
  kubectl -n "${NAMESPACE}" get pods -l 'app in (web,items,outfits,schedule)' -o wide || true
  return 1
}

wait_for_no_pending_app_pods

check_internal_health() {
  local svc="$1"
  local local_port="$2"
  local target_port="$3"
  local app_label="$4"
  local pf_pid=""
  local code="000"
  local attempts=10
  local i
  local pf_log
  pf_log="$(mktemp "/tmp/smoke-pf-${svc}.XXXX.log")"

  echo "Checking in-cluster health for ${svc} (app=${app_label}) -> /health"
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l "app=${app_label}" --timeout=120s >/dev/null
  kubectl -n "${NAMESPACE}" port-forward "deployment/${svc}" "${local_port}:${target_port}" >"${pf_log}" 2>&1 &
  pf_pid=$!

  # Wait until port-forward is actually ready.
  local ready=0
  for ((i=1; i<=30; i++)); do
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "port-forward for ${svc} exited early." >&2
      break
    fi
    if grep -Eq "Forwarding from (127\\.0\\.0\\.1|\\[::1\\]):${local_port}" "${pf_log}"; then
      ready=1
      break
    fi
    sleep 1
  done

  if [[ "${ready}" != "1" ]]; then
    echo "Internal health setup failed for ${svc}; port-forward did not become ready." >&2
    echo "port-forward log (${svc}):" >&2
    if [[ -f "${pf_log}" ]]; then
      sed 's/^/  /' "${pf_log}" >&2 || true
    fi
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  for ((i=1; i<=attempts; i++)); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${local_port}/health" || true)"
    if [[ "${code}" =~ ^2|3 ]]; then
      echo "Internal health OK for ${svc} (${code})"
      kill "${pf_pid}" >/dev/null 2>&1 || true
      wait "${pf_pid}" 2>/dev/null || true
      rm -f "${pf_log}" || true
      return 0
    fi
    sleep 2
  done

  kill "${pf_pid}" >/dev/null 2>&1 || true
  wait "${pf_pid}" 2>/dev/null || true
  rm -f "${pf_log}" || true
  echo "Internal health failed for ${svc}: /health returned ${code}" >&2
  return 1
}

check_internal_health "items" 18081 8081 "items"
check_internal_health "outfits" 18082 8082 "outfits"
check_internal_health "schedule" 18083 8083 "schedule"

LB_HOST="$(kubectl get ingress -n "${NAMESPACE}" "${PROJECT}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [[ -z "${LB_HOST}" ]]; then
  echo "Ingress ${NAMESPACE}/${PROJECT} has no load balancer hostname." >&2
  exit 1
fi
echo "Ingress LB: ${LB_HOST}"

SMOKE_BASE_HOST="${FRONTEND_HOST}"
SMOKE_CONNECT_TO=()

curl_code() {
  local url="$1"
  curl -sS "${SMOKE_CONNECT_TO[@]}" -o /dev/null -w '%{http_code}' "${url}" || true
}

front_code="$(curl_code "https://${SMOKE_BASE_HOST}")"
if [[ ! "${front_code}" =~ ^2|3 ]]; then
  echo "Primary frontend host check failed: https://${SMOKE_BASE_HOST} returned ${front_code}" >&2
  echo "Retrying via ALB using SNI host ${FRONTEND_HOST} -> ${LB_HOST}"
  # Keep URL/SNI/Host as FRONTEND_HOST so ACM cert validation passes,
  # but connect network path directly to the ALB hostname.
  SMOKE_BASE_HOST="${FRONTEND_HOST}"
  SMOKE_CONNECT_TO=(--connect-to "${FRONTEND_HOST}:443:${LB_HOST}:443")
  front_code="$(curl_code "https://${SMOKE_BASE_HOST}")"
fi
if [[ ! "${front_code}" =~ ^2|3 ]]; then
  echo "Frontend smoke failed: https://${SMOKE_BASE_HOST} returned ${front_code}" >&2
  exit 1
fi
echo "Frontend smoke OK (${front_code}) via ${SMOKE_BASE_HOST}"

check_api() {
  local path="$1"
  local attempts=12
  local sleep_s=5
  local code="000"
  local i
  for ((i=1; i<=attempts; i++)); do
    code="$(curl_code "https://${SMOKE_BASE_HOST}${path}")"
    # Accepts 2xx/3xx/4xx for smoke; retries transient transport/5xx.
    if [[ "${code}" != "000" && ! "${code}" =~ ^5 ]]; then
      echo "Backend route ${path} OK (${code}) via ${SMOKE_BASE_HOST} (attempt ${i}/${attempts})"
      return 0
    fi
    echo "Backend route ${path} not ready yet (${code}), retrying (${i}/${attempts})..."
    sleep "${sleep_s}"
  done
  echo "Backend smoke failed: https://${SMOKE_BASE_HOST}${path} returned ${code} after ${attempts} attempts" >&2
  exit 1
}

check_api "/api/v1/items"
check_api "/api/v1/outfits"
check_api "/api/v1/assignments"

resolve_rds_id() {
  local candidate="$1"
  local s
  s="$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${candidate}" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)"
  if [[ -n "${s}" && "${s}" != "None" ]]; then
    echo "${candidate}"
    return 0
  fi

  # Fallback: discover by tags used by Terraform (Project + Env).
  local discovered
  discovered="$(aws rds describe-db-instances --region "${REGION}" \
    --query "DBInstances[?contains(DBInstanceIdentifier, '${NAMESPACE}')].DBInstanceIdentifier" \
    --output text 2>/dev/null | awk '{print $1}')"
  if [[ -n "${discovered}" && "${discovered}" != "None" ]]; then
    echo "${discovered}"
    return 0
  fi
  echo "${candidate}"
  return 0
}

RDS_ID="$(resolve_rds_id "${RDS_ID}")"
rds_status="$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${RDS_ID}" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)"
if [[ "${rds_status}" != "available" ]]; then
  echo "RDS smoke failed: ${RDS_ID} status=${rds_status}" >&2
  exit 1
fi
echo "RDS smoke OK (${RDS_ID}: ${rds_status})"

echo "Smoke test passed for ${NAMESPACE}."
