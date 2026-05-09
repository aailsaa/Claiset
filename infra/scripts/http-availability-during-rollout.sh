#!/usr/bin/env bash
# Prints one HTTPS GET result per second to FRONTEND_HOST (/) for rollout / zero-downtime evidence.
# No inner retries — isolated 502 / ERR lines are real and defensible as "no sustained outage" in prose.
#
# Env:
#   FRONTEND_HOST — hostname only (example: app-dev.claiset.xyz) OR full URL
# Args:
#   $1 — optional max seconds (default 0 = until Ctrl+C)
#
# Optional debugging (shows why sustained HTTP ERR ≠ scale-down by itself):
#   HTTP_PROBE_DIAG=1 — print curl stderr once per probe when curl fails before an HTTP status
#
set -euo pipefail

HOST_OR_URL="${FRONTEND_HOST:-}"
SEC_MAX="${1:-0}"

if [[ -z "${HOST_OR_URL}" ]]; then
  echo "Set FRONTEND_HOST (e.g. app-dev.claiset.xyz)" >&2
  exit 1
fi

if [[ "${HOST_OR_URL}" == https://* || "${HOST_OR_URL}" == http://* ]]; then
  URL="${HOST_OR_URL}/"
else
  URL="https://${HOST_OR_URL}/"
fi

echo "Polling ${URL} every 1s (max_sec=${SEC_MAX}, 0=until Ctrl+C) — UTC timestamps"
echo "---"

samples=0
start_ts="$(date +%s)"
diag_tmp=""
if [[ "${HTTP_PROBE_DIAG:-}" == "1" ]]; then
  diag_tmp="$(mktemp)"
  trap '[[ -n "${diag_tmp:-}" ]] && rm -f "${diag_tmp}"' EXIT
fi

while true; do
  ts="$(date -u '+%H:%M:%S')"
  if [[ "${HTTP_PROBE_DIAG:-}" == "1" ]]; then
    rm -f "${diag_tmp}"
    if code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "${URL}" 2>"${diag_tmp}")"; then
      [[ -z "${code}" ]] && code="000"
    else
      code="ERR"
      curl_err=""
      curl_err="$(tr -d '\r' <"${diag_tmp}" | tail -n 1)"
      [[ -n "${curl_err}" ]] && echo "${ts} DIAG ${curl_err}" >&2
    fi
  else
    if code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "${URL}" 2>/dev/null)"; then
      [[ -z "${code}" ]] && code="000"
    else
      code="ERR"
    fi
  fi
  echo "${ts} HTTP ${code}"

  samples=$((samples + 1))
  if [[ "${SEC_MAX}" =~ ^[0-9]+$ ]] && [[ "${SEC_MAX}" -gt 0 ]]; then
    now="$(date +%s)"
    if [[ $((now - start_ts)) -ge "${SEC_MAX}" ]]; then
      echo "--- done (${samples} samples)"
      exit 0
    fi
  fi
  sleep 1
done
