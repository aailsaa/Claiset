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
RDS_ID="${RDS_INSTANCE_ID:-${PROJECT}-${NAMESPACE}}"

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
  local code
  code="$(curl_code "https://${SMOKE_BASE_HOST}${path}")"
  # Accepts 2xx/3xx/4xx for smoke; rejects transport failures/5xx.
  if [[ "${code}" == "000" || "${code}" =~ ^5 ]]; then
    echo "Backend smoke failed: https://${SMOKE_BASE_HOST}${path} returned ${code}" >&2
    exit 1
  fi
  echo "Backend route ${path} OK (${code}) via ${SMOKE_BASE_HOST}"
}

check_api "/api/v1/items"
check_api "/api/v1/outfits"
check_api "/api/v1/assignments"

rds_status="$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${RDS_ID}" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)"
if [[ "${rds_status}" != "available" ]]; then
  echo "RDS smoke failed: ${RDS_ID} status=${rds_status}" >&2
  exit 1
fi
echo "RDS smoke OK (${RDS_ID}: ${rds_status})"

echo "Smoke test passed for ${NAMESPACE}."
