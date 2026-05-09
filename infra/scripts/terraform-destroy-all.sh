#!/usr/bin/env bash
# Destroy one or more environments to stop AWS charges.
#
# Usage (from repo root):
#   export TF_STATE_BUCKET=your-bootstrap-bucket
#   export TF_LOCK_TABLE=your-bootstrap-lock-table
#   export AWS_REGION=us-east-1   # or your region
#   ./infra/scripts/terraform-destroy-all.sh           # destroys dev,qa,uat,prod (asks for confirmation)
#   ./infra/scripts/terraform-destroy-all.sh dev qa    # only destroy specific envs
#
# Notes:
# - Uses the same backend layout as promotion.yml: envs/<env>/terraform.tfstate
# - Pre-cleans Ingress in the env namespace and all Ingress + LoadBalancer Services in `monitoring` (observability Grafana ALB) before Terraform
# - In CI, set TF_DESTROY_AUTO_APPROVE=1 and pass env names (e.g. qa) to skip the prompt.
# - Run this from your laptop, not inside GitHub Actions (unless TF_DESTROY_AUTO_APPROVE=1).
# - Make sure no CI job is currently running terraform for these envs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="${TF_VAR_project:-claiset}"

STATE_BUCKET="${TF_STATE_BUCKET:-}"
LOCK_TABLE="${TF_LOCK_TABLE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "${STATE_BUCKET}" || -z "${LOCK_TABLE}" ]]; then
  echo "TF_STATE_BUCKET and TF_LOCK_TABLE must be set in the environment." >&2
  echo "Example:" >&2
  echo "  export TF_STATE_BUCKET=claiset-tf-state-... " >&2
  echo "  export TF_LOCK_TABLE=claiset-tf-locks" >&2
  exit 1
fi

ENVS=("$@")
if [[ ${#ENVS[@]} -eq 0 ]]; then
  ENVS=(dev qa uat prod)
fi

DESTROY_OPTS=()
if [[ "${TF_DESTROY_AUTO_APPROVE:-0}" == "1" ]]; then
  echo "TF_DESTROY_AUTO_APPROVE=1: destroying without confirmation: ${ENVS[*]}"
  DESTROY_OPTS=(-auto-approve)
else
  echo "About to destroy environments: ${ENVS[*]}"
  read -r -p "Type 'yes' to continue: " CONFIRM
  if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

cleanup_orphan_k8s_enis() {
  local env="$1"
  local vpc_ids vpc_id eni_ids eni

  # Find env VPC(s). Primary: Project/Env tags. Fallback: Name tag.
  vpc_ids="$(aws ec2 describe-vpcs --region "${AWS_REGION}" \
    --filters "Name=tag:Project,Values=${PROJECT}" "Name=tag:Env,Values=${env}" \
    --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)"
  if [[ -z "${vpc_ids}" || "${vpc_ids}" == "None" ]]; then
    vpc_ids="$(aws ec2 describe-vpcs --region "${AWS_REGION}" \
      --filters "Name=tag:Name,Values=${PROJECT}-${env}" \
      --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)"
  fi
  if [[ -z "${vpc_ids}" || "${vpc_ids}" == "None" ]]; then
    echo "No VPC found for env=${env}; skipping orphan ENI cleanup."
    return 0
  fi

  # Kubernetes / ALB controller can leave detached aws-K8S ENIs that block SG/subnet destroy.
  for vpc_id in ${vpc_ids}; do
    [[ -n "${vpc_id}" ]] || continue
    eni_ids="$(aws ec2 describe-network-interfaces --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" "Name=status,Values=available" \
      --query "NetworkInterfaces[?starts_with(Description, 'aws-K8S-')].NetworkInterfaceId" \
      --output text 2>/dev/null || true)"
    if [[ -z "${eni_ids}" || "${eni_ids}" == "None" ]]; then
      echo "No orphan aws-K8S ENIs found in VPC ${vpc_id}."
      continue
    fi
    echo "Deleting orphan aws-K8S ENIs in VPC ${vpc_id}: ${eni_ids}"
    for eni in ${eni_ids}; do
      [[ -n "${eni}" ]] || continue
      aws ec2 delete-network-interface --region "${AWS_REGION}" --network-interface-id "${eni}" >/dev/null || true
    done
  done
}

for ENV in "${ENVS[@]}"; do
  ENV_DIR="${ROOT_DIR}/infra/envs/${ENV}"
  if [[ ! -d "${ENV_DIR}" ]]; then
    echo "Skipping ${ENV}: ${ENV_DIR} does not exist."
    continue
  fi

  echo
  echo "=== Destroying ${ENV} ==="

  # Best-effort pre-cleanup in cluster to reduce ALB/ENI dependency leftovers that block subnet/IGW destroy.
  # App Ingress (ALB): namespace matches env name (dev/qa/uat/prod). Observability Grafana Ingress lives in monitoring.
  CLUSTER_NAME="${EXPECTED_CLUSTER_NAME:-claiset-${ENV}}"
  if command -v aws >/dev/null 2>&1 && command -v kubectl >/dev/null 2>&1; then
    if aws eks describe-cluster --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
      echo "Pre-cleanup (${ENV}): cluster=${CLUSTER_NAME} namespaces=${ENV},monitoring"
      aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null || true
      kubectl delete ingress claiset -n "${ENV}" --ignore-not-found=true --wait=true || true
      # Remove any LB Services that could keep ENIs/EIPs attached.
      kubectl get svc -n "${ENV}" -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | while IFS= read -r svc; do
            [[ -n "${svc}" ]] || continue
            kubectl delete svc "${svc}" -n "${ENV}" --ignore-not-found=true --wait=true || true
          done
      kubectl wait --for=delete ingress/claiset -n "${ENV}" --timeout=120s 2>/dev/null || true

      # Self-hosted Grafana (kube-prometheus-stack) Ingress is in monitoring, not env namespace — release ALBs early.
      # ALB controller TargetGroupBindings must go before Ingress finalizers clear; otherwise Helm/Terraform can sit on
      # `helm_release.kube_prometheus_stack` destroy for 45m+ with Ingress backends pointing at a deleted Service.
      if kubectl get ns monitoring >/dev/null 2>&1; then
        kubectl delete targetgroupbindings --all -n monitoring --ignore-not-found=true --wait=false 2>/dev/null || true
        kubectl delete ingress --all -n monitoring --ignore-not-found=true --wait=false || true
        # Wait for Ingress objects and ALB teardown (often >3m).
        for _ in $(seq 1 40); do
          rem="$(kubectl get ingress -n monitoring --no-headers 2>/dev/null | wc -l | tr -d ' ')"
          if [[ "${rem}" == "0" ]]; then
            break
          fi
          sleep 15
        done
        rem="$(kubectl get ingress -n monitoring --no-headers 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "${rem}" != "0" ]]; then
          echo "WARN: ${rem} Ingress object(s) still in namespace monitoring after pre-cleanup wait (~10m)." >&2
          echo "      Terraform can hang on helm_release.kube_prometheus_stack destroy. From another shell:" >&2
          echo "        kubectl delete targetgroupbindings --all -n monitoring --wait=false" >&2
          echo "        kubectl delete ingress --all -n monitoring --wait=false" >&2
          echo "      Then confirm: kubectl get ingress -n monitoring" >&2
          kubectl get ingress -n monitoring -o wide >&2 || true
        fi
        kubectl get svc -n monitoring -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
          | while IFS= read -r svc; do
              [[ -n "${svc}" ]] || continue
              kubectl delete svc "${svc}" -n monitoring --ignore-not-found=true --wait=true || true
            done
      fi
    fi
  fi

  (
    cd "${ENV_DIR}"
    terraform init \
      -backend-config="bucket=${STATE_BUCKET}" \
      -backend-config="key=envs/${ENV}/terraform.tfstate" \
      -backend-config="region=${AWS_REGION}" \
      -backend-config="dynamodb_table=${LOCK_TABLE}" \
      -backend-config="encrypt=true"

    # Phase 1: Kubernetes app + platform (Ingress/ALB, external-dns, cert automation, Prometheus/Grafana/Loki/Promtail when enabled).
    # If these modules are already gone, continue to full destroy.
    echo "Phase 1 destroy (${ENV}): app/platform resources"
    terraform destroy "${DESTROY_OPTS[@]}" \
      -target=module.app_bluegreen \
      -target=module.platform || true

    # Phase 2: full environment destroy.
    cleanup_orphan_k8s_enis "${ENV}"
    echo "Phase 2 destroy (${ENV}): full environment"
    if ! terraform destroy "${DESTROY_OPTS[@]}"; then
      # Clear detached aws-K8S ENIs that often block SG/subnet/VPC deletion with DependencyViolation.
      cleanup_orphan_k8s_enis "${ENV}"
      echo "Full destroy failed for ${ENV}; waiting and retrying once for eventual-consistency dependencies..."
      sleep 20
      terraform destroy "${DESTROY_OPTS[@]}"
    fi
  )
done

echo
echo "All requested environments processed."

