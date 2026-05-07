#!/usr/bin/env bash
# Run from an initialized Terraform env directory (e.g. infra/envs/dev), after terraform init:
#   bash ../../scripts/terraform-ecr-import-guard.sh
#
# If shared ECR repositories already exist in AWS but aren't in Terraform state (for example,
# created by CI bootstrap), Terraform create will fail with RepositoryAlreadyExistsException.
# This guard imports existing repositories into state so apply can converge.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${ECR_REPOSITORY_PREFIX:-claiset}"
SUFFIXES=(items outfits schedule web migrate)

echo "ECR import guard: prefix=${PREFIX} region=${REGION}"

in_state() {
  local addr="$1"
  terraform state show -no-color "${addr}" >/dev/null 2>&1
}

# Backend must be usable. First-ever apply has no state file yet; that's OK.
STATE_LIST_ERR=""
if ! STATE_LIST_ERR="$(terraform state list 2>&1 >/dev/null)"; then
  case "${STATE_LIST_ERR}" in
    *"no state file was found"*|*"state snapshot was empty"*|*"cannot read state"*)
      echo "ECR import guard: no existing state yet (fresh env), continuing."
      ;;
    *)
      echo "::error::Unable to read Terraform state (unexpected error). Run terraform init in this directory (and ensure backend env vars are set in CI) before running this guard." >&2
      echo "${STATE_LIST_ERR}" >&2
      exit 1
      ;;
  esac
fi

try_import() {
  local addr="$1" id="$2" desc="$3"

  if in_state "${addr}"; then
    echo "${desc} already managed in state, skipping import"
    return 0
  fi

  echo "Importing existing ${desc} into state"
  if terraform import "${addr}" "${id}"; then
    return 0
  fi

  # If another step imported it first, treat as OK.
  echo "Skipping ${desc}: import failed (may already be managed)" >&2
  return 0
}

for suffix in "${SUFFIXES[@]}"; do
  repo="${PREFIX}-${suffix}"
  addr="module.ecr.aws_ecr_repository.this[\"${suffix}\"]"
  if aws ecr describe-repositories --region "${REGION}" --repository-names "${repo}" >/dev/null 2>&1; then
    try_import "${addr}" "${repo}" "ECR repository ${repo}"
  fi
done

echo "ECR import guard OK."

