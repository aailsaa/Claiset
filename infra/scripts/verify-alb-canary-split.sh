#!/usr/bin/env bash
# Sample https://<frontend>/ with curl -I and count X-Claiset-SPA-Tier: stable|canary.
# Compare observed canary share to expected ALB weight; exit non-zero if far off (statistical guard).
#
# Requires nginx header from web image (SPA_TIER env) — see web/nginx.conf + docker-entrypoint.sh.
#
# Usage:
#   FRONTEND_HOST=app-uat.claiset.xyz ./infra/scripts/verify-alb-canary-split.sh --duration 90 --expected-canary-percent 10
#   (Use --expected-canary-percent 0 when weighted canary is off; expects zero canary hits.)
#   ./infra/scripts/verify-alb-canary-split.sh --host app-uat.claiset.xyz --requests 400 --expected-canary-percent 10
#
# Optional (flaky runner DNS to ALB, same idea as smoke-test-env.sh):
#   RESOLVE_IPV4=1.2.3.4   # dig the ALB; curl --resolve ${FRONTEND_HOST}:443:${RESOLVE_IPV4}
#
set -euo pipefail

HOST="${FRONTEND_HOST:-}"
EXPECTED_PCT=""
DURATION_SEC=""
REQUESTS=""
INTERVAL="${INTERVAL:-0.05}"
Z_THRESHOLD="${Z_THRESHOLD:-2.576}" # ~99% two-sided normal (tunable via env)
MIN_SAMPLES="${MIN_SAMPLES:-80}"
RESOLVE_IP="${RESOLVE_IP:-${RESOLVE_IPV4:-}}"

usage() {
  cat <<'EOF'
Verify ALB canary traffic share via X-Claiset-SPA-Tier response header (curl samples).

  FRONTEND_HOST=app-uat.claiset.xyz ./infra/scripts/verify-alb-canary-split.sh \
    --expected-canary-percent 10 --duration 90

  ./infra/scripts/verify-alb-canary-split.sh --host app-uat.claiset.xyz \
    --expected-canary-percent 10 --requests 500 --interval 0.05

  RESOLVE_IPV4=<alb-a-record> ./infra/scripts/verify-alb-canary-split.sh \
    --host app-uat.claiset.xyz --expected-canary-percent 10 --duration 120

Env: Z_THRESHOLD (default 2.576 ~99%), MIN_SAMPLES warn threshold, INTERVAL between curls.

Exit: 0 OK, 1 usage/curl failure, 2 split flagged off vs expected.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"; shift 2 ;;
    --expected-canary-percent|--expected)
      EXPECTED_PCT="${2:-}"; shift 2 ;;
    --duration|--seconds)
      DURATION_SEC="${2:-}"; shift 2 ;;
    --requests|-n)
      REQUESTS="${2:-}"; shift 2 ;;
    --interval)
      INTERVAL="${2:-}"; shift 2 ;;
    --resolve-ip)
      RESOLVE_IP="${2:-}"; shift 2 ;;
    --min-samples)
      MIN_SAMPLES="${2:-}"; shift 2 ;;
    --z-threshold)
      Z_THRESHOLD="${2:-}"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2
      usage ;;
  esac
done

if [[ -z "${HOST}" ]]; then
  echo "Set --host or FRONTEND_HOST (e.g. app-uat.claiset.xyz)." >&2
  exit 1
fi
if [[ -z "${EXPECTED_PCT}" ]]; then
  echo "Set --expected-canary-percent (1–50, matching TF_VAR_alb_web_canary_traffic_percent)." >&2
  exit 1
fi
if [[ ! "${EXPECTED_PCT}" =~ ^[0-9]+$ ]] || [[ "${EXPECTED_PCT}" -lt 0 ]] || [[ "${EXPECTED_PCT}" -gt 50 ]]; then
  echo "--expected-canary-percent must be 0–50 (Ingress/Terraform limit; got ${EXPECTED_PCT})." >&2
  exit 1
fi
if [[ -n "${DURATION_SEC}" && -n "${REQUESTS}" ]]; then
  echo "Use only one of --duration or --requests." >&2
  exit 1
fi
if [[ -z "${DURATION_SEC}" && -z "${REQUESTS}" ]]; then
  DURATION_SEC=60
fi

URL="https://${HOST}/"

curl_one() {
  local tier line
  if [[ -n "${RESOLVE_IP}" ]]; then
    line="$(curl -sSI --max-time 15 --connect-timeout 5 \
      --resolve "${HOST}:443:${RESOLVE_IP}" \
      "${URL}" 2>/dev/null | tr -d '\r' || true)"
  else
    line="$(curl -sSI --max-time 15 --connect-timeout 5 "${URL}" 2>/dev/null | tr -d '\r' || true)"
  fi
  tier="$(printf '%s\n' "${line}" | awk 'BEGIN{IGNORECASE=1} /^x-claiset-spa-tier:/ {print tolower($2); exit}')"
  printf '%s' "${tier}"
}

# --- sampling ---
stable=0
canary=0
unknown=0
total=0
start_ts="$(date +%s)"
end_ts="$start_ts"
if [[ -n "${DURATION_SEC}" ]]; then
  end_ts=$((start_ts + DURATION_SEC))
fi

echo "ALB canary split check: url=${URL} expected_canary≈${EXPECTED_PCT}%"
[[ -n "${RESOLVE_IP}" ]] && echo "Using --resolve ${HOST}:443:${RESOLVE_IP}"
if [[ -n "${DURATION_SEC}" ]]; then
  echo "Mode: time box ${DURATION_SEC}s (interval ${INTERVAL}s between requests)"
else
  echo "Mode: fixed ${REQUESTS} requests (interval ${INTERVAL}s)"
fi

while true; do
  now="$(date +%s)"
  if [[ -n "${DURATION_SEC}" ]]; then
    if (( now >= end_ts )); then
      break
    fi
  else
    if (( total >= REQUESTS )); then
      break
    fi
  fi

  tier="$(curl_one || printf '')"
  case "${tier}" in
    stable) stable=$((stable + 1)) ;;
    canary) canary=$((canary + 1)) ;;
    *) unknown=$((unknown + 1)) ;;
  esac
  total=$((total + 1))

  # Progress every 50 samples
  if (( total % 50 == 0 )); then
    echo "  samples=${total} stable=${stable} canary=${canary} unknown=${unknown}"
  fi

  if awk -v i="${INTERVAL}" 'BEGIN { exit (i > 0) ? 0 : 1 }'; then
    sleep "${INTERVAL}"
  fi
done

elapsed=$(( $(date +%s) - start_ts ))
echo "Done: elapsed=${elapsed}s samples=${total} stable=${stable} canary=${canary} unknown=${unknown}"

if [[ "${total}" -lt 1 ]]; then
  echo "FAIL: no samples collected." >&2
  exit 1
fi

unk_pct_raw="$(awk -v u="${unknown}" -v t="${total}" 'BEGIN { if (t>0) printf "%.4f", 100*u/t; else print 0 }')"
unk_flag="$(awk -v u="${unk_pct_raw}" 'BEGIN { if (u > 5.0) exit 1; exit 0 }')" || {
  echo "WARN: unknown/missing tier on ${unk_pct_raw}% of requests (header missing or curl errors?)." >&2
}

classified=$((stable + canary))
if [[ "${classified}" -lt 1 ]]; then
  echo "FAIL: no stable|canary responses (all unknown). Check URL, TLS, and X-Claiset-SPA-Tier header." >&2
  exit 1
fi

obs_pct="$(awk -v c="${canary}" -v n="${classified}" 'BEGIN { printf "%.4f", 100*c/n }')"
echo "Observed canary share (unknown excluded): ${obs_pct}% (${canary}/${classified})"

if [[ "${classified}" -lt "${MIN_SAMPLES}" ]]; then
  echo "WARN: classified samples ${classified} < MIN_SAMPLES=${MIN_SAMPLES}; z-test is noisy. Increase --duration or --requests." >&2
fi

# Binomial normal approx: SE = sqrt(p*(1-p)/n), z = |p_hat - p0| / SE
p0="$(awk -v e="${EXPECTED_PCT}" 'BEGIN { printf "%.8f", e/100 }')"
phat="$(awk -v c="${canary}" -v n="${classified}" 'BEGIN { printf "%.8f", c/n }')"

flag=0
reason=""
if [[ "${EXPECTED_PCT}" -eq 0 ]]; then
  if [[ "${canary}" -gt 0 ]]; then
    flag=1
    reason="expected 0% canary but saw ${canary} canary responses"
  fi
else
  se="$(awk -v p="${p0}" -v n="${classified}" 'BEGIN { printf "%.10f", sqrt(p*(1-p)/n) }')"
  if awk -v s="${se}" 'BEGIN { if (s < 1e-12) exit 1; exit 0 }'; then
    z="$(awk -v ph="${phat}" -v p="${p0}" -v s="${se}" 'BEGIN { printf "%.4f", (ph-p)/s }')"
    zabs="$(awk -v z="${z}" 'BEGIN { a=z; if (a<0) a=-a; printf "%.4f", a }')"
    if ! awk -v za="${zabs}" -v zt="${Z_THRESHOLD}" 'BEGIN { if (za > zt) exit 1; exit 0 }'; then
      se_pct="$(awk -v s="${se}" 'BEGIN { printf "%.5f", 100*s }')"
      flag=1
      reason="|z|=${zabs} > threshold ${Z_THRESHOLD} (observed ${obs_pct}% vs expected ${EXPECTED_PCT}%, SE≈${se_pct}% points)"
    fi
  else
    echo "WARN: could not compute SE (degenerate); skip z-test." >&2
  fi
fi

if [[ "${flag}" -eq 1 ]]; then
  echo "FLAG: split looks off — ${reason}" >&2
  echo "Hint: ALB weights are configured shares, not guarantees per small N; raise samples or widen Z_THRESHOLD if this is a false alarm." >&2
  exit 2
fi

echo "OK: observed canary ${obs_pct}% is within normal variation vs expected ${EXPECTED_PCT}% (n=${classified}, Z_THRESHOLD=${Z_THRESHOLD})."
exit 0
