#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tf_dir="$repo_root/terraform/environments/homelab"

required=(
  versions.tf
  provider.tf
  variables.tf
  main.tf
  outputs.tf
  backend.tf
  terraform.tfvars.example
)

for file in "${required[@]}"; do
  test -f "$tf_dir/$file" || {
    printf 'missing Terraform file: %s\n' "$file" >&2
    exit 1
  }
done

terraform -chdir="$tf_dir" fmt -check -recursive
terraform -chdir="$tf_dir" init -backend=false
terraform -chdir="$tf_dir" validate

if rg -n 'latest|main|master' "$tf_dir" "$repo_root/terraform/modules"; then
  printf 'unlocked version found in Terraform\n' >&2
  exit 1
fi

printf 'terraform static validation: PASS\n'
