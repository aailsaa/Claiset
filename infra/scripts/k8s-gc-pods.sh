#!/usr/bin/env bash
# Best-effort cleanup of terminal pods that can accumulate during churn and
# contribute to scheduler "Too many pods" pressure on small-node clusters.
#
# Usage:
#   K8S_NAMESPACES="prod monitoring platform kube-system" bash ../../scripts/k8s-gc-pods.sh

set -euo pipefail

namespaces="${K8S_NAMESPACES:-prod monitoring}"

for ns in ${namespaces}; do
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    continue
  fi
  echo "k8s-gc-pods: namespace=${ns}"
  # Remove terminal pods that are safe to garbage-collect.
  kubectl -n "${ns}" delete pod --field-selector=status.phase=Failed --ignore-not-found=true >/dev/null 2>&1 || true
  # Evicted pods are Failed with reason=Evicted; explicit pass for clarity.
  kubectl -n "${ns}" get pods --no-headers 2>/dev/null | awk '$3=="Evicted"{print $1}' | xargs -r kubectl -n "${ns}" delete pod >/dev/null 2>&1 || true
done

echo "k8s-gc-pods: done"
