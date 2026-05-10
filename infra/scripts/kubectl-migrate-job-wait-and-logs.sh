#!/usr/bin/env bash
# Wait for migrate Job completion and print logs — only when the Job was recreated recently (schema change replace).
#
# Uses Job .metadata.creationTimestamp: if older than MIGRATE_JOB_FRESH_MAX_AGE_SECONDS (default 7200),
# assumes no migrate replace this terraform apply — skip kubectl wait + exit 0.
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

echo "Migrate log capture (schema-driven): cluster=${CLUSTER} ns=${NAMESPACE} job=${JOB_NAME} wait=${WAIT_SEC}s fresh_max_age=${MAX_AGE}s"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null

if ! kubectl get "job/${JOB_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Job ${NAMESPACE}/${JOB_NAME} not found." >&2
  exit 1
fi

CREATED_RAW="$(kubectl get "job/${JOB_NAME}" -n "${NAMESPACE}" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)"
NOW_EPOCH="$(date -u +%s)"
START_EPOCH=0
if [[ -n "${CREATED_RAW}" ]]; then
  START_EPOCH="$(epoch_from_rfc3339 "${CREATED_RAW}")"
fi

if [[ "${START_EPOCH}" -eq 0 ]]; then
  echo "Cannot parse Job creationTimestamp; running full wait..."
  gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
  gh_step_summary ""
  gh_step_summary "**Ran (fallback)** — could not parse \`creationTimestamp\`; running full wait. Check step log for migrate output."
else
  AGE=$((NOW_EPOCH - START_EPOCH))
  if [[ "${AGE}" -gt "${MAX_AGE}" ]]; then
    echo "Migrate Job ${JOB_NAME} is not fresh (created ~${AGE}s ago vs max_age=${MAX_AGE}s)."
    echo "Skipping long wait — no terraform replace detected for this workflow (typically unchanged cmd/migrate/schema.sql)."
    echo "To force migrate logs: bump schema.sql or terraform apply -replace='module.eks_app.kubernetes_job.migrate[0]'."
    echo ""
    gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
    gh_step_summary ""
    gh_step_summary "**Skipped** — Job is older than the freshness window (\`${MAX_AGE}s\`). Likely **no \`schema.sql\` change**, so Terraform did not replace the Job."
    gh_step_summary ""
    gh_step_summary "When **\`schema.sql\` does change**, this step will wait for completion and **print migrate logs** in the step output above."
    gh_step_summary ""
    exit 0
  fi
  echo "Job looks fresh (~${AGE}s since creationTimestamp); waiting for Complete..."
  gh_step_summary "## Migrate (${NAMESPACE}/${JOB_NAME})"
  gh_step_summary ""
  gh_step_summary "**Ran** — fresh Job (~\`${AGE}s\` since \`creationTimestamp\`). Migrate output follows in this step’s log (between the \`kubectl logs\` banners)."
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
