#!/usr/bin/env bash
# Wait for migrate Job completion when needed; skip when this commit's schema is already wired on the Job.
#
# Primary signal: kubernetes_job migrate has annotation claiset.dev/migrate-schema-sha (Terraform migrate_replace_signal).
# If it matches sha256(cmd/migrate/schema.sql) from the repo checkout, no new migrate run is expected — skip.
# If hashes differ but the Job is fresh, wait + logs (new migrate). If hashes differ and Job is stale, fail —
# Terraform should have recreated the Job (replace_triggered_by terraform_data).
#
# Fallback (no annotation or non-hash placeholder): reuse creationTimestamp freshness window.
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

# --- Decision: schema annotation vs checkout (authoritative when both are SHA256 hex) ---
if is_sha256_hex "${REPO_SHA}" && is_sha256_hex "${JOB_ANNO}"; then
  if [[ "${REPO_SHA}" == "${JOB_ANNO}" ]]; then
    echo "migrate-schema-sha on Job matches checkout (${REPO_SHA:0:12}…); no recreate needed — skipping wait."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary ""
    gh_step_summary "**Skipped** — \`${SCHEMA_ANNO_KEY}\` matches \`cmd/migrate/schema.sql\` in this checkout (${REPO_SHA:0:12}…)."
    gh_step_summary ""
    exit 0
  fi
  echo "Schema drift: checkout sha256=${REPO_SHA} Job annotation=${JOB_ANNO}"
  if [[ "${START_EPOCH}" -eq 0 ]]; then
    echo "Cannot parse creationTimestamp — running full wait + logs..."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary ""
    gh_step_summary "**Ran (mismatch)** — Job annotation differs from repo but age unknown; waiting and streaming logs."
  elif [[ "${AGE}" -le "${MAX_AGE}" ]]; then
    echo "Job is fresh (~${AGE}s); waiting for Complete (migrate for new schema)."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary ""
    gh_step_summary "**Ran** — schema hash on Job differs from checkout; waited for migration. Logs below."
  else
    echo "ERROR: Repo schema (${REPO_SHA}) does not match Job (${JOB_ANNO}) but migrate Job metadata is stale (~${AGE}s)." >&2
    echo "Terraform should recreate job/${JOB_NAME} when cmd/migrate/schema.sql changes dev (replace_triggered_by)." >&2
    echo "Fix: terraform apply dev from infra/envs/dev or: terraform apply -replace='module.eks_app.kubernetes_job.migrate[0]'" >&2
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME}) — failed"
    gh_step_summary "**Error** — schema hash mismatch and Job was not recreated. See step log."
    exit 1
  fi

elif is_sha256_hex "${REPO_SHA}" && ! is_sha256_hex "${JOB_ANNO}"; then
  echo "No usable ${SCHEMA_ANNO_KEY} on Job yet (${JOB_ANNO:-<missing>}); using freshness window only until the next terraform apply annotates migrate."
elif ! is_sha256_hex "${REPO_SHA}" && [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file missing at ${SCHEMA_FILE}; using freshness heuristic only." >&2
fi

if [[ "${START_EPOCH}" -eq 0 ]]; then
  echo "Cannot parse Job creationTimestamp; running full wait..."
  gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
  gh_step_summary ""
  gh_step_summary "**Ran (fallback)** — could not parse \`creationTimestamp\`; full wait."
else
  if [[ "${AGE}" -gt "${MAX_AGE}" ]]; then
    # Only fatal here if both sides are authoritative SHA hex and still mismatched (drift handled above failed).
    if is_sha256_hex "${REPO_SHA}" && is_sha256_hex "${JOB_ANNO}" && [[ "${JOB_ANNO}" != "${REPO_SHA}" ]]; then
      echo "Stale Job and annotation/checkout still differ after drift handling — exiting error." >&2
      exit 1
    fi
    echo "Migrate Job ${JOB_NAME} is not fresh (created ~${AGE}s ago vs max_age=${MAX_AGE}s)."
    echo "Skipping long wait — no recent Terraform recreate (and no schema-hash match path applied)."
    echo "To force migrate logs: terraform apply -replace='module.eks_app.kubernetes_job.migrate[0]'."
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary ""
    gh_step_summary "**Skipped** — Job older than \`${MAX_AGE}s\` (legacy freshness heuristic)."
    gh_step_summary ""
    exit 0
  fi
  echo "Job looks fresh (~${AGE}s since creationTimestamp); waiting for Complete..."
  gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
  gh_step_summary ""
  gh_step_summary "**Ran** — fresh Job per age window. Migrate logs in step output."
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
