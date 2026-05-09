#!/usr/bin/env bash
# Ensure frontend DNS records exist in Route53 by pointing them at the live Ingress ALB.
#
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after apply:
#   K8S_APP_NAMESPACE=dev bash ../../scripts/route53-ingress-records-guard.sh
#
# Expected env (fallbacks provided where possible):
# - AWS_REGION (default us-east-1)
# - DOMAIN_ROOT or TF_VAR_domain_root
# - FRONTEND_SUBDOMAIN or TF_VAR_frontend_subdomain (empty means apex is canonical for that env)
# - UPDATE_APEX_DNS=true only for prod: upsert claiset.xyz + www to this ALB. Default false so
#   dev/qa/uat runs do not steal the apex from production.
# - ROUTE53_HOSTED_ZONE_ID or TF_VAR_route53_hosted_zone_id (optional; looked up if unset)
# - K8S_APP_NAMESPACE (default TF_VAR_env or dev)
# - K8S_INGRESS_NAME (default TF_VAR_project or claiset)
# - EXPECTED_CLUSTER_NAME (optional, used to auto-run `aws eks update-kubeconfig` in CI)
#
# Ingress ALBs appear asynchronously; this script waits for .status.loadBalancer before upsert:
# - ROUTE53_GUARD_ALB_WAIT_SECONDS (default 900)
# - ROUTE53_GUARD_ALB_POLL_INTERVAL (default 10)
# - ROUTE53_GUARD_AWSLB_ZONE_POLL_SECONDS (default 180) — ELBv2 may lag Ingress hostname
# - ROUTE53_GUARD_ALLOW_MISSING_ALB (default false): if true, exit 0 if hostname never appears

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_APP_NAMESPACE:-${TF_VAR_env:-dev}}"
INGRESS_NAME="${K8S_INGRESS_NAME:-${TF_VAR_project:-claiset}}"
DOMAIN_ROOT="${DOMAIN_ROOT:-${TF_VAR_domain_root:-}}"
ALB_WAIT_SECS="${ROUTE53_GUARD_ALB_WAIT_SECONDS:-900}"
ALB_POLL_SECS="${ROUTE53_GUARD_ALB_POLL_INTERVAL:-10}"
ZONE_WAIT_SECS="${ROUTE53_GUARD_AWSLB_ZONE_POLL_SECONDS:-180}"
ALLOW_MISSING_ALB="${ROUTE53_GUARD_ALLOW_MISSING_ALB:-false}"
# Preserve intentionally empty FRONTEND_SUBDOMAIN (apex as frontend). Use -v so "" from the caller is not replaced.
if [[ ! -v FRONTEND_SUBDOMAIN ]]; then
  FRONTEND_SUBDOMAIN="${TF_VAR_frontend_subdomain:-app}"
fi
UPDATE_APEX_DNS="${UPDATE_APEX_DNS:-false}"
HOSTED_ZONE_ID="${ROUTE53_HOSTED_ZONE_ID:-${TF_VAR_route53_hosted_zone_id:-}}"
CLUSTER_NAME="${EXPECTED_CLUSTER_NAME:-}"

if [[ -z "${DOMAIN_ROOT}" ]]; then
  echo "Route53 guard: DOMAIN_ROOT/TF_VAR_domain_root is empty; skipping DNS upsert."
  exit 0
fi

if [[ -n "${FRONTEND_SUBDOMAIN}" ]]; then
  FRONTEND_HOST="${FRONTEND_SUBDOMAIN}.${DOMAIN_ROOT}"
else
  FRONTEND_HOST="${DOMAIN_ROOT}"
fi

echo "Route53 guard: namespace=${NAMESPACE} ingress=${INGRESS_NAME} domain=${DOMAIN_ROOT} frontend=${FRONTEND_HOST} update_apex_dns=${UPDATE_APEX_DNS} region=${REGION}"

fetch_ingress_alb_dns() {
  kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
}

if [[ -n "${CLUSTER_NAME}" ]]; then
  echo "Route53 guard: kubeconfig for cluster ${CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" >/dev/null
elif ! command -v kubectl >/dev/null 2>&1; then
  echo "::error::Route53 guard: kubectl not found; set EXPECTED_CLUSTER_NAME so we can bootstrap kubeconfig." >&2
  exit 1
fi

ALB_DNS=""
deadline=$(( $(date +%s) + ALB_WAIT_SECS ))
while true; do
  ALB_DNS="$(fetch_ingress_alb_dns)"
  if [[ -n "${ALB_DNS}" ]]; then
    echo "Route53 guard: ingress ALB hostname: ${ALB_DNS}"
    break
  fi
  now_ts="$(date +%s)"
  if [[ "${now_ts}" -ge "${deadline}" ]]; then
    echo "::warning::Route53 guard: Ingress has no ALB hostname after ${ALB_WAIT_SECS}s (${NAMESPACE}/${INGRESS_NAME})." >&2
    kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o wide >&2 || true
    if [[ "${ALLOW_MISSING_ALB}" == "true" ]]; then
      echo "Route53 guard: ROUTE53_GUARD_ALLOW_MISSING_ALB=true → skipping DNS upsert."
      exit 0
    fi
    exit 1
  fi
  echo "Route53 guard: waiting for Ingress loadBalancer hostname (${now_ts}<${deadline})..."
  sleep "${ALB_POLL_SECS}"
done

if [[ -z "${HOSTED_ZONE_ID}" ]]; then
  HOSTED_ZONE_ID="$(aws route53 list-hosted-zones-by-name \
    --dns-name "${DOMAIN_ROOT}" \
    --query "HostedZones[?Name=='${DOMAIN_ROOT}.']|[0].Id" \
    --output text)"
  HOSTED_ZONE_ID="${HOSTED_ZONE_ID#/hostedzone/}"
fi

if [[ -z "${HOSTED_ZONE_ID}" || "${HOSTED_ZONE_ID}" == "None" ]]; then
  echo "::warning::Route53 guard: no hosted zone id found for ${DOMAIN_ROOT}; skipping."
  exit 0
fi

ALB_ZONE_ID=""
zone_deadline=$(( $(date +%s) + ZONE_WAIT_SECS ))
while true; do
  ALB_ZONE_ID="$(aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "LoadBalancers[?DNSName=='${ALB_DNS}']|[0].CanonicalHostedZoneId" \
    --output text 2>/dev/null || true)"
  if [[ -n "${ALB_ZONE_ID}" && "${ALB_ZONE_ID}" != "None" ]]; then
    break
  fi
  znow="$(date +%s)"
  if [[ "${znow}" -ge "${zone_deadline}" ]]; then
    echo "::error::Route53 guard: timed out (${ZONE_WAIT_SECS}s) resolving ELBv2 CanonicalHostedZoneId for ${ALB_DNS}." >&2
    exit 1
  fi
  echo "Route53 guard: waiting for ELBv2 describe-load-balancers to list ${ALB_DNS} ..."
  sleep 5
done

upsert_alias() {
  local record_name="$1"
  local record_type="$2"
  aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "{
      \"Comment\": \"Upsert ${record_name} -> ${ALB_DNS}\",
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"${record_name}\",
          \"Type\": \"${record_type}\",
          \"AliasTarget\": {
            \"HostedZoneId\": \"${ALB_ZONE_ID}\",
            \"DNSName\": \"${ALB_DNS}\",
            \"EvaluateTargetHealth\": false
          }
        }
      }]
    }" >/dev/null
}

# Canonical hostname for this environment (always).
upsert_alias "${FRONTEND_HOST}" "A"
upsert_alias "${FRONTEND_HOST}" "AAAA"

# Apex + www only when deploying prod (or other primary env); avoids non-prod CI stealing root DNS.
if [[ "${UPDATE_APEX_DNS}" == "true" ]]; then
  upsert_alias "${DOMAIN_ROOT}" "A"
  upsert_alias "${DOMAIN_ROOT}" "AAAA"
  upsert_alias "www.${DOMAIN_ROOT}" "A"
  upsert_alias "www.${DOMAIN_ROOT}" "AAAA"
  echo "Route53 guard OK: upserted frontend + apex + www in zone ${HOSTED_ZONE_ID} -> ${ALB_DNS}."
else
  echo "Route53 guard OK: upserted frontend host only (apex/www unchanged) in zone ${HOSTED_ZONE_ID} -> ${ALB_DNS}."
fi
