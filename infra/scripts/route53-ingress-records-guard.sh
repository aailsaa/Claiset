#!/usr/bin/env bash
# Ensure frontend DNS records exist in Route53 by pointing them at the live Ingress ALB.
#
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after apply:
#   K8S_APP_NAMESPACE=dev bash ../../scripts/route53-ingress-records-guard.sh
#
# Expected env (fallbacks provided where possible):
# - AWS_REGION (default us-east-1)
# - DOMAIN_ROOT or TF_VAR_domain_root
# - FRONTEND_SUBDOMAIN or TF_VAR_frontend_subdomain (empty means apex is canonical)
# - ROUTE53_HOSTED_ZONE_ID or TF_VAR_route53_hosted_zone_id (optional; looked up if unset)
# - K8S_APP_NAMESPACE (default TF_VAR_env or dev)
# - K8S_INGRESS_NAME (default TF_VAR_project or claiset)
# - EXPECTED_CLUSTER_NAME (optional, used to auto-run `aws eks update-kubeconfig` in CI)

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_APP_NAMESPACE:-${TF_VAR_env:-dev}}"
INGRESS_NAME="${K8S_INGRESS_NAME:-${TF_VAR_project:-claiset}}"
DOMAIN_ROOT="${DOMAIN_ROOT:-${TF_VAR_domain_root:-}}"
FRONTEND_SUBDOMAIN="${FRONTEND_SUBDOMAIN:-${TF_VAR_frontend_subdomain:-app}}"
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

echo "Route53 guard: namespace=${NAMESPACE} ingress=${INGRESS_NAME} domain=${DOMAIN_ROOT} frontend=${FRONTEND_HOST} region=${REGION}"

ALB_DNS=""
if command -v kubectl >/dev/null 2>&1; then
  ALB_DNS="$(kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
fi

# CI runners may not have kubeconfig preconfigured even though Terraform already applied.
if [[ -z "${ALB_DNS}" && -n "${CLUSTER_NAME}" ]]; then
  echo "Route53 guard: attempting kubeconfig bootstrap for cluster ${CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" >/dev/null
  ALB_DNS="$(kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
fi

if [[ -z "${ALB_DNS}" ]]; then
  echo "Route53 guard: ingress has no load balancer hostname yet; skipping."
  exit 0
fi

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

ALB_ZONE_ID="$(aws elbv2 describe-load-balancers --region "${REGION}" \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}']|[0].CanonicalHostedZoneId" \
  --output text)"
if [[ -z "${ALB_ZONE_ID}" || "${ALB_ZONE_ID}" == "None" ]]; then
  echo "::warning::Route53 guard: could not resolve ALB hosted zone id for ${ALB_DNS}; skipping."
  exit 0
fi

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

# Canonical + convenience hostnames
upsert_alias "${FRONTEND_HOST}" "A"
upsert_alias "${FRONTEND_HOST}" "AAAA"
upsert_alias "${DOMAIN_ROOT}" "A"
upsert_alias "${DOMAIN_ROOT}" "AAAA"
upsert_alias "www.${DOMAIN_ROOT}" "A"
upsert_alias "www.${DOMAIN_ROOT}" "AAAA"

echo "Route53 guard OK: upserted A/AAAA alias records in zone ${HOSTED_ZONE_ID} -> ${ALB_DNS}."
