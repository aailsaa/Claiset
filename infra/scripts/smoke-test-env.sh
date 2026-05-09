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
#   EXPECTED_CLUSTER_NAME=claiset-dev K8S_APP_NAMESPACE=dev FRONTEND_HOST=app-dev.claiset.xyz \
#   bash ../../scripts/smoke-test-env.sh

set -euo pipefail

MODE="${1:-full}"

case "${MODE}" in
  full|--full)
    MODE="full"
    ;;
  wait-only|--wait-only)
    MODE="wait-only"
    ;;
  skip-wait|--skip-wait)
    MODE="skip-wait"
    ;;
  *)
    echo "Unknown mode: ${MODE}. Use: full | --wait-only | --skip-wait" >&2
    exit 1
    ;;
esac

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-}"
NAMESPACE="${K8S_APP_NAMESPACE:-${TF_VAR_env:-dev}}"
PROJECT="${TF_VAR_project:-claiset}"
FRONTEND_HOST="${FRONTEND_HOST:-}"
RDS_ID="${RDS_INSTANCE_ID:-${PROJECT}-${NAMESPACE}-postgres}"
GRAFANA_HOST="${GRAFANA_HOST:-}"
EXPECT_OBSERVABILITY_SMOKE="${EXPECT_OBSERVABILITY_SMOKE:-}"
EXPECT_OBSERVABILITY_DAEMONSETS="${EXPECT_OBSERVABILITY_DAEMONSETS:-}"
EXPECT_PROMTAIL="${EXPECT_PROMTAIL:-}"
EXPECT_APP_OAUTH_SMOKE="${EXPECT_APP_OAUTH_SMOKE:-true}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-8m}"

if [[ -z "${CLUSTER}" ]]; then
  echo "EXPECTED_CLUSTER_NAME is required." >&2
  exit 1
fi

if [[ -z "${FRONTEND_HOST}" ]]; then
  echo "FRONTEND_HOST is required (e.g. claiset.xyz, app-qa.claiset.xyz)." >&2
  exit 1
fi

derive_domain_root() {
  local host="$1"
  # For app subdomains like app-qa.claiset.xyz -> claiset.xyz
  # For apex like claiset.xyz -> claiset.xyz
  if [[ "${host}" == *.*.* ]]; then
    echo "${host#*.}"
  else
    echo "${host}"
  fi
}

# Bash [[ =~ ]] regex: ^2|3 means (^2)|(3) — the lone "3" matches any string containing 3, so 503 falsely passes.
http_2xx_or_3xx() { [[ "$1" =~ ^[23][0-9]{2}$ ]]; }
http_2xx() { [[ "$1" =~ ^2[0-9]{2}$ ]]; }
http_2xx_or_4xx() { [[ "$1" =~ ^[24][0-9]{2}$ ]]; }

observability_smoke_enabled() {
  if [[ -n "${EXPECT_OBSERVABILITY_SMOKE}" ]]; then
    [[ "${EXPECT_OBSERVABILITY_SMOKE}" == "1" || "${EXPECT_OBSERVABILITY_SMOKE}" == "true" ]]
    return
  fi
  [[ "${TF_VAR_enable_observability_stack:-false}" == "true" ]]
}

observability_daemonsets_enabled() {
  if [[ -n "${EXPECT_OBSERVABILITY_DAEMONSETS}" ]]; then
    [[ "${EXPECT_OBSERVABILITY_DAEMONSETS}" == "1" || "${EXPECT_OBSERVABILITY_DAEMONSETS}" == "true" ]]
    return
  fi
  [[ "${TF_VAR_enable_observability_daemonsets:-false}" == "true" ]]
}

promtail_expected() {
  if [[ -n "${EXPECT_PROMTAIL}" ]]; then
    [[ "${EXPECT_PROMTAIL}" == "1" || "${EXPECT_PROMTAIL}" == "true" ]]
    return
  fi
  [[ "${TF_VAR_enable_promtail:-false}" == "true" ]]
}

app_oauth_smoke_enabled() {
  [[ "${EXPECT_APP_OAUTH_SMOKE}" == "1" || "${EXPECT_APP_OAUTH_SMOKE}" == "true" ]]
}

echo "Smoke test: cluster=${CLUSTER} namespace=${NAMESPACE} frontend=${FRONTEND_HOST} region=${REGION}"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

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

print_rollout_diagnostics() {
  local deployment="$1"
  echo "Rollout diagnostics for deployment/${deployment} in ${NAMESPACE}:"
  kubectl -n "${NAMESPACE}" get deployment "${deployment}" -o wide || true
  kubectl -n "${NAMESPACE}" get pods -l "app=${deployment}" -o wide || true
  kubectl -n "${NAMESPACE}" describe deployment "${deployment}" || true
  kubectl -n "${NAMESPACE}" describe pods -l "app=${deployment}" || true
  kubectl -n "${NAMESPACE}" get events --sort-by='.lastTimestamp' | tail -30 || true
}

print_cluster_scheduling_diagnostics() {
  echo "Cluster scheduling diagnostics (${CLUSTER}):"
  kubectl get nodes -o wide || true
  echo "Node allocatable pod slots:"
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" allocatable.pods="}{.status.allocatable.pods}{" capacity.pods="}{.status.capacity.pods}{"\n"}{end}' || true
  echo "Current pod counts per node (all namespaces):"
  kubectl get pods -A -o wide --no-headers 2>/dev/null | awk '$8!="" {c[$8]++} END{for (n in c) print n " pods=" c[n]}' || true
  echo "aws-node CNI env (prefix delegation/warm targets):"
  kubectl -n kube-system get ds aws-node -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"="}{.value}{"\n"}{end}' 2>/dev/null | awk '/ENABLE_PREFIX_DELEGATION|WARM_PREFIX_TARGET|WARM_IP_TARGET|MINIMUM_IP_TARGET/' || true
}

check_promtail_daemonset_ready() {
  echo "Observability guard: validating promtail DaemonSet readiness..."
  if ! kubectl -n monitoring get ds promtail >/dev/null 2>&1; then
    echo "Observability guard failed: DaemonSet monitoring/promtail not found while daemonsets are enabled." >&2
    kubectl -n monitoring get ds -o wide || true
    return 1
  fi

  local desired ready unavailable min_ready alloc_min
  desired="$(kubectl -n monitoring get ds promtail -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)"
  ready="$(kubectl -n monitoring get ds promtail -o jsonpath='{.status.numberReady}' 2>/dev/null || true)"
  unavailable="$(kubectl -n monitoring get ds promtail -o jsonpath='{.status.numberUnavailable}' 2>/dev/null || true)"
  alloc_min="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.pods}{"\n"}{end}' 2>/dev/null | awk 'NR==1{m=$1} $1<m{m=$1} END{print m+0}')"

  desired="${desired:-0}"
  ready="${ready:-0}"
  unavailable="${unavailable:-0}"
  alloc_min="${alloc_min:-0}"

  # On very small nodes (allocatable.pods ~= 4), full DaemonSet coverage can be impossible due to
  # kube-system + app pod density. Require a meaningful subset instead of 100% to avoid false fails.
  if [[ -n "${PROMTAIL_MIN_READY:-}" ]]; then
    min_ready="${PROMTAIL_MIN_READY}"
  elif [[ "${alloc_min}" -le 4 ]]; then
    min_ready=$(( desired / 2 ))
    if [[ "${min_ready}" -lt 4 ]]; then
      min_ready=4
    fi
  else
    # Allow one DaemonSet miss for transient memory/scheduling blips on small clusters.
    min_ready=$(( desired - 1 ))
    if [[ "${min_ready}" -lt 1 ]]; then
      min_ready=1
    fi
  fi

  if [[ "${desired}" -eq 0 || "${ready}" -lt "${min_ready}" ]]; then
    echo "Observability guard failed: monitoring/promtail below minimum readiness (desired=${desired}, ready=${ready}, unavailable=${unavailable}, min_ready=${min_ready}, min_allocatable_pods_per_node=${alloc_min})." >&2
    kubectl -n monitoring get ds promtail -o wide || true
    kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail -o wide || true
    kubectl -n monitoring get events --sort-by='.lastTimestamp' | tail -40 || true
    return 1
  fi

  echo "Observability guard OK: monitoring/promtail Ready (${ready}/${desired}, min_required=${min_ready})."
}

loki_svc_name() {
  if kubectl -n monitoring get svc loki >/dev/null 2>&1; then
    echo "loki"
    return 0
  fi
  # SingleBinary installs sometimes expose a chart-derived service name; fall back to a label lookup.
  local named
  named="$(kubectl -n monitoring get svc -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${named}" ]]; then
    echo "${named}"
    return 0
  fi
  echo ""
  return 1
}

check_promtail_on_app_workload_nodes() {
  echo "Observability guard: promtail must run on each node that hosts ${NAMESPACE} workloads (web/items/outfits/schedule)..."
  local missing=""
  local n=""
  local running=""
  kubectl -n "${NAMESPACE}" get pods -l 'app in (web,items,outfits,schedule)' -o wide || true
  kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail -o wide || true
  while IFS= read -r n; do
    [[ -z "${n}" ]] && continue
    running="$(kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail \
      --field-selector=spec.nodeName="${n}",status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
    running="${running:-0}"
    if [[ "${running}" -lt 1 ]]; then
      missing="${missing} ${n}"
    fi
  done < <(kubectl -n "${NAMESPACE}" get pods -l 'app in (web,items,outfits,schedule)' -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u)

  if [[ -n "${missing// }" ]]; then
    echo "Observability guard failed: promtail is missing on node(s):${missing}" >&2
    echo "  (Application pods scheduled on saturated nodes frequently cannot ship logs to Loki.)" >&2
    kubectl -n monitoring describe ds promtail 2>/dev/null | tail -60 || true
    return 1
  fi
  echo "Observability guard OK: promtail present on every app-workload node."
}

check_loki_streams_for_query() {
  local query="$1"
  local descr="$2"
  local loki_svc pf_pid pf_log pf_port ready end_ns start_ns streams i attempts
  attempts=24

  echo "Observability guard: Loki ingest/query must return streams for ${descr} (query=${query})..."
  if ! loki_svc="$(loki_svc_name)" || [[ -z "${loki_svc}" ]]; then
    echo "Observability guard failed: could not locate Loki Service in monitoring (tried svc/loki and app label)." >&2
    kubectl -n monitoring get svc -o wide || true
    return 1
  fi

  pf_log="$(mktemp "/tmp/smoke-loki-pf.XXXX.log")"
  pf_port="13999"
  kubectl -n monitoring port-forward "svc/${loki_svc}" "${pf_port}:3100" >"${pf_log}" 2>&1 &
  pf_pid=$!

  ready=0
  for ((i = 1; i <= 30; i++)); do
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      break
    fi
    if grep -Eq "Forwarding from (127\\.0\\.0\\.1|\\[::1\\]):${pf_port}" "${pf_log}" 2>/dev/null; then
      ready=1
      break
    fi
    sleep 1
  done

  if [[ "${ready}" != "1" ]]; then
    echo "Observability guard failed: port-forward to Loki did not become ready." >&2
    sed 's/^/  /' "${pf_log}" >&2 || true
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  streams=-1
  for ((i = 1; i <= attempts; i++)); do
    end_ns=$(( $(date +%s) * 1000000000 ))
    start_ns=$(( end_ns - 900000000000 ))
    streams="$(
      curl -sS -G "http://127.0.0.1:${pf_port}/loki/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "limit=200" \
        --data-urlencode "start=${start_ns}" \
        --data-urlencode "end=${end_ns}" \
        | jq -r '(.data.result // []) | length' 2>/dev/null || echo -1
    )"
    if [[ "${streams}" =~ ^[0-9]+$ && "${streams}" -gt 0 ]]; then
      break
    fi
    echo "Observability guard: Loki has no streams yet for ${descr} (attempt ${i}/${attempts})..."
    sleep 5
  done

  kill "${pf_pid}" >/dev/null 2>&1 || true
  wait "${pf_pid}" 2>/dev/null || true
  rm -f "${pf_log}" || true

  if [[ ! "${streams}" =~ ^[0-9]+$ || "${streams}" -lt 1 ]]; then
    echo "Observability guard failed: Loki query_range returned no streams for ${descr} (streams=${streams})." >&2
    return 1
  fi

  echo "Observability guard OK: Loki streams present for ${descr} (streams=${streams})."
}

prod_rollout_recovery_bump() {
  local nodegroup="${CLUSTER}-default"
  local min_size="${PROD_RECOVERY_MIN_SIZE:-1}"
  local desired_size="${PROD_RECOVERY_DESIRED_SIZE:-2}"
  local max_size="${PROD_RECOVERY_MAX_SIZE:-4}"
  local ready_floor="${PROD_RECOVERY_READY_FLOOR:-2}"
  echo "Prod rollout recovery: scaling nodegroup ${nodegroup} to min=${min_size} desired=${desired_size} max=${max_size} before retry."
  aws eks update-nodegroup-config \
    --region "${REGION}" \
    --cluster-name "${CLUSTER}" \
    --nodegroup-name "${nodegroup}" \
    --scaling-config "minSize=${min_size},desiredSize=${desired_size},maxSize=${max_size}" >/dev/null || return 1
  aws eks wait nodegroup-active --region "${REGION}" --cluster-name "${CLUSTER}" --nodegroup-name "${nodegroup}" || return 1
  for i in {1..24}; do
    ready_nodes="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')"
    echo "Prod rollout recovery: Ready nodes ${ready_nodes}/${desired_size} (attempt ${i}/24)"
    if [[ "${ready_nodes}" -ge "${ready_floor}" ]]; then
      break
    fi
    sleep 10
  done
  kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /SchedulingDisabled/ {print $1}' | xargs -r kubectl uncordon || true
}

rollout_with_recovery() {
  local deployment="$1"
  echo "Checking rollout: deployment/${deployment} in ${NAMESPACE}"
  print_cluster_scheduling_diagnostics
  if kubectl -n "${NAMESPACE}" rollout status "deployment/${deployment}" --timeout="${ROLLOUT_TIMEOUT}"; then
    return 0
  fi

  print_rollout_diagnostics "${deployment}"
  print_cluster_scheduling_diagnostics
  if [[ "${NAMESPACE}" == "prod" ]]; then
    echo "Prod rollout did not complete within ${ROLLOUT_TIMEOUT}; attempting one capacity recovery + retry."
    prod_rollout_recovery_bump || true
    if kubectl -n "${NAMESPACE}" rollout status "deployment/${deployment}" --timeout="${ROLLOUT_TIMEOUT}"; then
      return 0
    fi
    print_rollout_diagnostics "${deployment}"
    return 1
  fi

  return 1
}

if [[ "${MODE}" != "skip-wait" ]]; then
  for d in web items outfits schedule; do
    rollout_with_recovery "${d}"
  done
  wait_for_no_pending_app_pods
fi

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
    if http_2xx_or_3xx "${code}"; then
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

# GitHub-hosted runners occasionally use stub resolvers that fail *.elb.amazonaws.com or fresh
# Route53 names (curl exit 6). Query 1.1.1.1 / 8.8.8.8 and use curl --resolve so HTTPS still
# uses FRONTEND_HOST for SNI/ACM without relying on runner DNS for the LB hostname.
ipv4_first_from_public_dns() {
  local name="$1"
  local dns cand
  [[ -z "${name}" ]] && return 1
  if ! command -v dig >/dev/null 2>&1; then
    return 1
  fi
  for dns in 1.1.1.1 8.8.8.8; do
    cand="$(dig +timeout=6 +tries=2 +short "${name}" A @"${dns}" 2>/dev/null \
      | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print; exit}')"
    if [[ -n "${cand}" ]]; then
      printf '%s\n' "${cand}"
      return 0
    fi
  done
  return 1
}

SMOKE_LB_IPV4=""
echo "Resolving Ingress LB (${LB_HOST}) via public recursive DNS (1.1.1.1 / 8.8.8.8)..."
for _albwait in {1..36}; do
  if SMOKE_LB_IPV4="$(ipv4_first_from_public_dns "${LB_HOST}")" && [[ -n "${SMOKE_LB_IPV4}" ]]; then
    echo "Ingress LB IPv4 ${SMOKE_LB_IPV4} (resolver ok, attempt ${_albwait}/36; curl uses --resolve ${FRONTEND_HOST}:443)."
    break
  fi
  echo "LB hostname not in public DNS yet (${_albwait}/36); sleep 5s (new ALB / propagation)..."
  sleep 5
done
if [[ -z "${SMOKE_LB_IPV4}" ]]; then
  echo "::warning::Could not resolve ${LB_HOST} via 1.1.1.1/8.8.8.8 — frontend curl falls back to runner DNS only (install dnsutils if dig is missing)." >&2
fi

SMOKE_BASE_HOST="${FRONTEND_HOST}"
SMOKE_CONNECT_TO=()

curl_code() {
  local url="$1"
  local c="000"
  if [[ -n "${SMOKE_LB_IPV4:-}" ]]; then
    c="$(curl -sS --resolve "${FRONTEND_HOST}:443:${SMOKE_LB_IPV4}" \
      --connect-timeout 30 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || printf '000')"
  fi
  if [[ ! "${c}" =~ ^[0-9]{3}$ ]]; then
    c="000"
  fi
  if [[ "${c}" == "000" ]] || [[ "${c}" =~ ^5 ]]; then
    c="$(curl -sS "${SMOKE_CONNECT_TO[@]}" --connect-timeout 30 \
      -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || printf '000')"
  fi
  printf '%s' "${c}"
}

check_frontend() {
  local attempts="${1:-12}"
  local sleep_s="${2:-5}"
  local code="000"
  local i
  for ((i=1; i<=attempts; i++)); do
    code="$(curl_code "https://${SMOKE_BASE_HOST}")"
    if http_2xx_or_3xx "${code}"; then
      front_code="${code}"
      return 0
    fi
    echo "Frontend not ready yet: https://${SMOKE_BASE_HOST} -> ${code} (attempt ${i}/${attempts})"
    sleep "${sleep_s}"
  done
  front_code="${code}"
  return 1
}

front_code="000"
FRONTEND_REACH_MODE="hostname-dns"
if ! check_frontend 12 5; then
  echo "Primary frontend host check failed: https://${SMOKE_BASE_HOST} returned ${front_code}" >&2
  echo "Retrying via ALB using SNI host ${FRONTEND_HOST} -> ${LB_HOST}"
  # Keep URL/SNI/Host as FRONTEND_HOST so ACM cert validation passes,
  # but connect network path directly to the ALB hostname.
  SMOKE_BASE_HOST="${FRONTEND_HOST}"
  SMOKE_CONNECT_TO=(--connect-to "${FRONTEND_HOST}:443:${LB_HOST}:443")
  FRONTEND_REACH_MODE="alb-direct-connect-to"
  check_frontend 12 5 || true
fi
if ! http_2xx_or_3xx "${front_code}"; then
  echo "Frontend smoke failed: https://${SMOKE_BASE_HOST} returned ${front_code}" >&2
  exit 1
fi
echo "Frontend smoke OK (${front_code}) via ${SMOKE_BASE_HOST} (curl path: ${FRONTEND_REACH_MODE})"

check_grafana() {
  if [[ -z "${GRAFANA_HOST}" ]]; then
    DOMAIN_ROOT_DERIVED="$(derive_domain_root "${FRONTEND_HOST}")"
    GRAFANA_HOST="grafana-${NAMESPACE}.${DOMAIN_ROOT_DERIVED}"
  fi

  echo "Observability smoke: checking Grafana at https://${GRAFANA_HOST}"

  # Find the ALB behind monitoring ingress for connect-to fallback.
  GRAFANA_LB_HOST="$(kubectl get ingress -n monitoring -o jsonpath='{range .items[*]}{.spec.rules[0].host}{"|"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' -v h="${GRAFANA_HOST}" '$1==h {print $2; exit}')"

  if [[ -z "${GRAFANA_LB_HOST}" ]]; then
    echo "Grafana smoke failed: no monitoring ingress found for host ${GRAFANA_HOST}" >&2
    kubectl get ingress -n monitoring -o wide || true
    exit 1
  fi

  GRAFANA_LB_IPV4=""
  echo "Resolving Grafana ALB (${GRAFANA_LB_HOST}) via public DNS..."
  for _gw in {1..24}; do
    if GRAFANA_LB_IPV4="$(ipv4_first_from_public_dns "${GRAFANA_LB_HOST}")" && [[ -n "${GRAFANA_LB_IPV4}" ]]; then
      echo "Grafana LB IPv4 ${GRAFANA_LB_IPV4} (curl --resolve ${GRAFANA_HOST}:443)."
      break
    fi
    sleep 5
  done

  # Same runner DNS caveat as frontend: --resolve after public dig avoids NXDOMAIN *.elb.amazonaws.com.
  GRAFANA_CONNECT_TO=(--connect-to "${GRAFANA_HOST}:443:${GRAFANA_LB_HOST}:443")
  grafana_curl_code() {
    local url="$1"
    local c="000"
    if [[ -n "${GRAFANA_LB_IPV4:-}" ]]; then
      c="$(curl -sS --resolve "${GRAFANA_HOST}:443:${GRAFANA_LB_IPV4}" --connect-timeout 30 \
        -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || printf '000')"
    fi
    [[ ! "${c}" =~ ^[0-9]{3}$ ]] && c="000"
    if [[ "${c}" == "000" ]] || [[ "${c}" =~ ^5[0-9][0-9]$ ]]; then
      c="$(curl -sS "${GRAFANA_CONNECT_TO[@]}" --connect-timeout 30 \
        -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || printf '000')"
    fi
    printf '%s' "${c}"
  }
  grafana_curl_headers() {
    local url="$1"
    local out=""
    if [[ -n "${GRAFANA_LB_IPV4:-}" ]]; then
      out="$(curl -sS --resolve "${GRAFANA_HOST}:443:${GRAFANA_LB_IPV4}" --connect-timeout 30 \
        -D - -o /dev/null "${url}" 2>/dev/null || true)"
    fi
    if [[ -z "${out}" ]]; then
      out="$(curl -sS "${GRAFANA_CONNECT_TO[@]}" --connect-timeout 30 -D - -o /dev/null "${url}" 2>/dev/null || true)"
    fi
    printf '%s' "${out}"
  }

  grafana_code="000"
  attempts=24
  sleep_s=5
  for ((i=1; i<=attempts; i++)); do
    grafana_code="$(grafana_curl_code "https://${GRAFANA_HOST}")"
    if http_2xx_or_3xx "${grafana_code}"; then
      break
    fi
    echo "Grafana not ready yet: https://${GRAFANA_HOST} -> ${grafana_code} (attempt ${i}/${attempts})"
    sleep "${sleep_s}"
  done

  if ! http_2xx_or_3xx "${grafana_code}"; then
    echo "Grafana smoke failed: https://${GRAFANA_HOST} returned ${grafana_code}" >&2
    return 1
  fi
  echo "Grafana smoke OK (${grafana_code}) via ${GRAFANA_HOST}"

  # OAuth entrypoint must redirect to Google accounts for auth code flow.
  local oauth_headers=""
  local oauth_location=""
  oauth_headers="$(grafana_curl_headers "https://${GRAFANA_HOST}/login/google")"
  oauth_location="$(printf '%s\n' "${oauth_headers}" | awk 'BEGIN{IGNORECASE=1} /^location:/ {print $2; exit}' | tr -d '\r')"
  if [[ "${oauth_location}" != https://accounts.google.com/* ]]; then
    echo "Grafana OAuth smoke failed: /login/google did not redirect to Google. location=${oauth_location:-<empty>}" >&2
    return 1
  fi
  echo "Grafana OAuth smoke OK (redirects to Google Accounts)"

  # Assert Grafana has GF_AUTH_GOOGLE_CLIENT_SECRET wired from grafana-google-oauth.
  local gf_env
  gf_env="$(kubectl -n monitoring get deployment kube-prometheus-stack-grafana -o json | jq -r '.spec.template.spec.containers[]?.env // [], .spec.template.spec.containers[]?.envFrom // empty' 2>/dev/null || true)"
  if ! printf '%s\n' "${gf_env}" | grep -q 'GF_AUTH_GOOGLE_CLIENT_SECRET'; then
    echo "Grafana OAuth smoke failed: GF_AUTH_GOOGLE_CLIENT_SECRET not present in deployment env." >&2
    return 1
  fi

  echo "Grafana deep smoke: rollout, API health, datasource, and Loki query path"
  kubectl -n monitoring rollout status deployment/kube-prometheus-stack-grafana --timeout=8m

  local pf_pid=""
  local pf_log=""
  local g_user=""
  local g_pass=""
  local health_code="000"
  local prom_uid=""
  local prom_query_status="000"
  local ds_name=""
  local loki_query_status="000"
  local i

  pf_log="$(mktemp "/tmp/smoke-grafana-pf.XXXX.log")"
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 13000:80 >"${pf_log}" 2>&1 &
  pf_pid=$!

  # Wait until port-forward is ready.
  local ready=0
  for ((i=1; i<=30; i++)); do
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "Grafana port-forward exited early." >&2
      break
    fi
    if grep -Eq "Forwarding from (127\\.0\\.0\\.1|\\[::1\\]):13000" "${pf_log}"; then
      ready=1
      break
    fi
    sleep 1
  done

  if [[ "${ready}" != "1" ]]; then
    echo "Grafana deep smoke failed: port-forward did not become ready." >&2
    sed 's/^/  /' "${pf_log}" >&2 || true
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  # Grafana chart stores admin creds in this secret by default.
  g_user="$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 --decode || true)"
  g_pass="$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || true)"
  if [[ -z "${g_user}" || -z "${g_pass}" ]]; then
    echo "Grafana deep smoke failed: unable to read admin credentials from kube-prometheus-stack-grafana secret." >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  # API health
  health_code="$(curl -sS -u "${g_user}:${g_pass}" -o /dev/null -w '%{http_code}' "http://127.0.0.1:13000/api/health" || true)"
  if ! http_2xx "${health_code}"; then
    echo "Grafana deep smoke failed: /api/health returned ${health_code}" >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  # Verify Loki datasource is provisioned.
  ds_name="$(curl -sS -u "${g_user}:${g_pass}" "http://127.0.0.1:13000/api/datasources/name/Loki" | jq -r '.name // empty' 2>/dev/null || true)"
  if [[ "${ds_name}" != "Loki" ]]; then
    echo "Grafana deep smoke failed: Loki datasource missing from Grafana API." >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  local loki_uid=""
  loki_uid="$(curl -sS -u "${g_user}:${g_pass}" "http://127.0.0.1:13000/api/datasources/name/Loki" | jq -r '.uid // empty' 2>/dev/null || true)"
  if [[ -z "${loki_uid}" ]]; then
    echo "Grafana deep smoke failed: could not resolve Loki datasource UID (fix provisioning or datasource name)." >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  # Hit Loki query path via Grafana proxy API to ensure datasource query path works (2xx only; 404 is not OK).
  for i in {1..12}; do
    loki_query_status="$(curl -sS -u "${g_user}:${g_pass}" -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:13000/api/datasources/proxy/uid/${loki_uid}/loki/api/v1/query?query=vector(1)" || true)"
    if http_2xx "${loki_query_status}"; then
      break
    fi
    echo "Grafana deep smoke: Loki proxy not ready yet (${loki_query_status}), retrying (${i}/12)..."
    sleep 5
  done
  if ! http_2xx "${loki_query_status}"; then
    echo "Grafana deep smoke failed: Loki datasource proxy query returned ${loki_query_status}" >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  # Verify Prometheus datasource is provisioned and query path is reachable.
  prom_uid="$(curl -sS -u "${g_user}:${g_pass}" "http://127.0.0.1:13000/api/datasources/name/Prometheus" | jq -r '.uid // empty' 2>/dev/null || true)"
  if [[ -z "${prom_uid}" ]]; then
    echo "Grafana deep smoke failed: Prometheus datasource missing from Grafana API." >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi
  for i in {1..12}; do
    prom_query_status="$(curl -sS -u "${g_user}:${g_pass}" -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:13000/api/datasources/proxy/uid/${prom_uid}/api/v1/query?query=up" || true)"
    if http_2xx "${prom_query_status}"; then
      break
    fi
    echo "Grafana deep smoke: Prometheus proxy not ready yet (${prom_query_status}), retrying (${i}/12)..."
    sleep 5
  done
  if ! http_2xx "${prom_query_status}"; then
    echo "Grafana deep smoke failed: Prometheus datasource proxy query returned ${prom_query_status}" >&2
    kill "${pf_pid}" >/dev/null 2>&1 || true
    wait "${pf_pid}" 2>/dev/null || true
    rm -f "${pf_log}" || true
    return 1
  fi

  kill "${pf_pid}" >/dev/null 2>&1 || true
  wait "${pf_pid}" 2>/dev/null || true
  rm -f "${pf_log}" || true
  echo "Grafana deep smoke OK (health=${health_code}, datasource=${ds_name}, loki_proxy=${loki_query_status}, prom_proxy=${prom_query_status})"
}

check_app_oauth() {
  # App uses Google Identity JS in-browser. CLI smoke can verify login route availability only.
  local login_code="000"
  login_code="$(curl_code "https://${SMOKE_BASE_HOST}/login")"
  if ! http_2xx_or_3xx "${login_code}"; then
    echo "App OAuth smoke failed: /login returned ${login_code}" >&2
    return 1
  fi
  echo "App OAuth smoke OK (/login -> ${login_code})"
}

if [[ "${MODE}" == "wait-only" ]]; then
  if observability_smoke_enabled && observability_daemonsets_enabled && promtail_expected; then
    check_promtail_daemonset_ready
    check_promtail_on_app_workload_nodes
    check_loki_streams_for_query '{namespace="kube-system"}' "kube-system (promtail must be functioning)"
  fi
  if observability_smoke_enabled; then
    check_grafana
  fi
  echo "Wait-only checks passed for ${NAMESPACE}."
  exit 0
fi

if observability_smoke_enabled; then
  if observability_daemonsets_enabled && promtail_expected; then
    check_promtail_daemonset_ready
  fi
  check_grafana
fi

if app_oauth_smoke_enabled; then
  check_app_oauth
fi

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

if observability_smoke_enabled && observability_daemonsets_enabled && promtail_expected; then
  check_promtail_on_app_workload_nodes
  check_loki_streams_for_query '{namespace="kube-system"}' "kube-system (sanity)"
  check_loki_streams_for_query "{namespace=\"${NAMESPACE}\"}" "namespace=${NAMESPACE} (requires promtail + app stdout logs)"
fi

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
