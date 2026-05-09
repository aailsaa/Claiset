#!/usr/bin/env bash
# One-time per environment after renaming the app workloads module to module "eks_app":
# renames every state address module.app_bluegreen.* → module.eks_app.*
#
# Usage:
#   cd infra/envs/dev   # or qa, uat, prod
#   bash ../../scripts/terraform-state-mv-module-to-eks-app.sh
#
set -euo pipefail

old="module.app_bluegreen"
new="module.eks_app"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform not found on PATH" >&2
  exit 1
fi

addrs=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && addrs+=("${line}")
done < <(terraform state list | grep "^${old}\\." || true)

if ((${#addrs[@]} == 0)); then
  echo "No state addresses start with ${old}. — nothing to migrate (already on ${new} or empty state)."
  exit 0
fi

for addr in "${addrs[@]}"; do
  postfix="${addr#"${old}"}"
  dest="${new}${postfix}"
  echo "terraform state mv '${addr}' '${dest}'"
  terraform state mv "${addr}" "${dest}"
done

echo "Renamed ${#addrs[@]} state object(s) from ${old} to ${new}."
