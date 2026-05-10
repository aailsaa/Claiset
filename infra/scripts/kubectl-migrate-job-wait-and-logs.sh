#!/usr/bin/env bash
# Wait for migrate Job completion when Terraform recreated job/migrate for this revision.
#
# claiset.dev/migrate-schema-sha on the Job equals sha256(schema.sql) after apply. That is TRUE both when:
#   (a) Nothing changed — old Job, same hash as checkout → skip long wait.
#   (b) Schema changed — NEW Job, same NEW hash as checkout → MUST wait + logs (do not skip).
# Distinction: Job metadata.creationTimestamp age vs MIGRATE_JOB_FRESH_MAX_AGE_SECONDS (default 7200).
#
# Drift: checkout hash != Job annotation + stale Job → fail (Terraform should have replaced the Job).
#
# Usage:
#   EXPECTED_CLUSTER_NAME=claiset-dev AWS_REGION=us-east-1 \
#     bash infra/scripts/kubectl-migrate-job-wait-and-logs.sh dev migrate 720 7200
#
# Args: namespace job_name [wait_secs] [fresh_max_age_secs]
#
set -euo pipefail

NAMESPACE="${1:?namespace}"
JOB_NAME="${2:?job-name}"
WAIT_SEC="${3:-720}"
MAX_AGE="${4:-${MIGRATE_JOB_FRESH_MAX_AGE_SECONDS:-7200}}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${EXPECTED_CLUSTER_NAME:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHEMA_FILE="${MIGRATE_SCHEMA_FILE:-${REPO_ROOT}/cmd/migrate/schema.sql}"

SCHEMA_ANNO_KEY='claiset.dev/migrate-schema-sha'

if [[ -z "${CLUSTER}" ]]; then
  echo "EXPECTED_CLUSTER_NAME is required." >&2
  exit 1
fi

epoch_from_rfc3339() {
  python3 -c 'import datetime,sys; print(int(datetime.datetime.strptime(sys.argv[1][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$1" 2>/dev/null \
    || echo "0"
}

gh_step_summary() {
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] && return 0
  printf '%s\n' "$*" >>"${GITHUB_STEP_SUMMARY}"
}

is_sha256_hex() {
  [[ -n "${1:-}" ]] && [[ "${#1}" -eq 64 ]] && [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

schema_sha_repo() {
  [[ -f "$SCHEMA_FILE" ]] || return 0
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$SCHEMA_FILE" | awk '{print $1}'
  else
    shasum -a 256 "$SCHEMA_FILE" | awk '{print $1}'
  fi
}

job_schema_annotation() {
  kubectl get "job/${JOB_NAME}" -n "${NAMESPACE}" -o json \
    | python3 -c 'import sys,json; job=json.load(sys.stdin); ann=job.get("metadata",{}).get("annotations",{}); print(ann.get("'"${SCHEMA_ANNO_KEY}"'", "") or "")'
}

echo "Migrate log capture: cluster=${CLUSTER} ns=${NAMESPACE} job=${JOB_NAME} wait=${WAIT_SEC}s fresh_max_age=${MAX_AGE}s schema_file=${SCHEMA_FILE}"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

if ! kubectl get "job/${JOB_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Job ${NAMESPACE}/${JOB_NAME} not found." >&2
  exit 1
fi

REPO_SHA="$(schema_sha_repo || true)"

CREATED_RAW="$(kubectl get "job/${JOB_NAME}" -n "${NAMESPACE}" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)"
NOW_EPOCH="$(date -u +%s)"
START_EPOCH=0
if [[ -n "${CREATED_RAW}" ]]; then
  START_EPOCH="$(epoch_from_rfc3339 "${CREATED_RAW}")"
fi
AGE=0
if [[ "${START_EPOCH}" -ne 0 ]]; then
  AGE=$((NOW_EPOCH - START_EPOCH))
fi

JOB_ANNO="$(job_schema_annotation || true)"

both_hex() { is_sha256_hex "${REPO_SHA}" && is_sha256_hex "${JOB_ANNO}"; }

# --- Both SHA hex: mismatch => drift or fresh recreate ---
if both_hex && [[ "${REPO_SHA}" != "${JOB_ANNO}" ]]; then
  echo "Schema drift: checkout=${REPO_SHA} Job ${SCHEMA_ANNO_KEY}=${JOB_ANNO} (age ~${AGE}s)"
  if [[ "${START_EPOCH}" -eq 0 ]]; then
    echo "Cannot parse creationTimestamp — running full wait + logs..."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary "**Ran** — hash mismatch; could not parse Job age. Logs below."
  elif [[ "${AGE}" -le "${MAX_AGE}" ]]; then
    echo "Job is fresh (~${AGE}s); waiting for Complete (new schema / recreate in progress)."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary "**Ran** — annotation differs from checkout on a fresh Job. Logs below."
  else
    echo "ERROR: Repo schema (${REPO_SHA}) does not match Job (${JOB_ANNO}) but migrate Job is stale (~${AGE}s)." >&2
    echo "Terraform should replace job/${JOB_NAME} when cmd/migrate/schema.sql changes (dev replace_triggered_by)." >&2
    echo "Fix: terraform apply from infra/envs/dev or: terraform apply -replace='module.eks_app.kubernetes_job.migrate[0]'" >&2
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME}) — failed"
    gh_step_summary "**Error** — hash mismatch and Job not recreated. See log."
    exit 1
  fi

# --- Both SHA hex and MATCH: skip only if Job is stale (same revision already deployed long ago) ---
elif both_hex && [[ "${REPO_SHA}" == "${JOB_ANNO}" ]]; then
  if [[ "${START_EPOCH}" -ne 0 ]] && [[ "${AGE}" -gt "${MAX_AGE}" ]]; then
    echo "migrate-schema-sha matches checkout (${REPO_SHA:0:12}…) and Job is stale (~${AGE}s > ${MAX_AGE}s) — no recreate this pipeline; skipping wait."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary "**Skipped** — same schema revision as Job; Terraform did not recreate migrate (unchanged \`schema.sql\` or apply skipped workloads)."
    exit 0
  fi
  if [[ "${START_EPOCH}" -eq 0 ]]; then
    echo "migrate-schema-sha matches checkout but creationTimestamp could not be parsed — waiting for Complete + logs (safe path)."
  else
    echo "migrate-schema-sha matches checkout and Job is fresh (~${AGE}s ≤ ${MAX_AGE}s) — waiting for Complete + logs (schema rollout or recent Job recreate)."
  fi
  gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
  gh_step_summary "**Ran** — hash matches on a fresh Job (or unparsed age); waited for migration (instant if already Complete). Logs below."

# --- Missing / legacy annotation: freshness heuristic only ---
elif is_sha256_hex "${REPO_SHA}" && ! is_sha256_hex "${JOB_ANNO}"; then
  echo "No usable ${SCHEMA_ANNO_KEY} on Job (${JOB_ANNO:-<missing>}); using creationTimestamp freshness only."
  if [[ "${START_EPOCH}" -eq 0 ]]; then
    echo "Cannot parse creationTimestamp; running full wait..."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary "**Ran (fallback)** — no annotation; full wait."
  elif [[ "${AGE}" -gt "${MAX_AGE}" ]]; then
    echo "Migrate Job ${JOB_NAME} not fresh (~${AGE}s) — skipping wait until terraform applies annotations."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary "**Skipped** — stale Job, no schema-sha annotation yet."
    exit 0
  fi
  echo "Job looks fresh (~${AGE}s); waiting for Complete..."
  gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
  gh_step_summary "**Ran** — freshness fallback. Logs below."

elif ! is_sha256_hex "${REPO_SHA}" && [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file missing at ${SCHEMA_FILE}; using freshness only." >&2
  if [[ "${START_EPOCH}" -eq 0 ]]; then
    :
  elif [[ "${AGE}" -gt "${MAX_AGE}" ]]; then
    echo "Skipping — stale Job." >&2
    exit 0
  fi
else
  # Repo sha exists but weird; fall through to wait
  echo "Non-standard schema hash in repo; attempting wait + logs." >&2
fi

complete_ok=0
if kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout="${WAIT_SEC}s" 2>/dev/null; then
  complete_ok=1
else
  echo "Job not Complete within ${WAIT_SEC}s (may have Failed)." >&2
  kubectl describe "job/${JOB_NAME}" -n "${NAMESPACE}" || true
  kubectl get pods -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" -o wide || true
  kubectl wait --for=condition=failed "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=30s 2>/dev/null || true
fi

echo ""
echo "========== kubectl logs job/${JOB_NAME} (${NAMESPACE}) =========="
if kubectl logs -n "${NAMESPACE}" "job/${JOB_NAME}" --all-containers=true --tail=500 2>/dev/null; then
  :
else
  POD="$(kubectl get pods -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${POD}" ]]; then
    kubectl logs -n "${NAMESPACE}" "pod/${POD}" --all-containers=true --tail=500 2>/dev/null || true
  else
    echo "(no pod logs)"
  fi
fi
echo "========== end migrate logs =========="

if [[ "${complete_ok}" == "1" ]]; then
  exit 0
fi
exit 1
