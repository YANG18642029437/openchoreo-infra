#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tf_dir="$repo_root/terraform/environments/homelab"
modules_dir="$repo_root/terraform/modules"

required=(
  versions.tf
  provider.tf
  variables.tf
  main.tf
  outputs.tf
  backend.tf
  terraform.tfvars.example
  .terraform.lock.hcl
)

for file in "${required[@]}"; do
  test -f "$tf_dir/$file" || {
    printf 'missing Terraform file: %s\n' "$file" >&2
    exit 1
  }
done

test -d "$modules_dir" || {
  printf 'missing Terraform modules directory: %s\n' "$modules_dir" >&2
  exit 1
}

command -v ruby >/dev/null 2>&1 || {
  printf 'missing command: ruby\n' >&2
  exit 1
}

ruby - "$tf_dir" <<'RUBY'
tf_dir = ARGV.fetch(0)
versions = File.readlines(File.join(tf_dir, 'versions.tf'))
exact_constraint = /^\s*version\s*=\s*"=\s*[0-9]+\.[0-9]+\.[0-9]+"\s*(?:#.*)?$/
abort 'proxmox provider version must use an exact constraint: = x.y.z' unless versions.any? { |line| line.match?(exact_constraint) }

lock_lines = File.readlines(File.join(tf_dir, '.terraform.lock.hcl'))
provider_index = lock_lines.index { |line| line.match?(/^provider\s+"registry\.terraform\.io\/bpg\/proxmox"\s*\{\s*$/) }
abort 'missing bpg/proxmox provider in Terraform lock file' unless provider_index
locked_version = lock_lines[(provider_index + 1)..].find { |line| line.match?(/^\s*version\s*=/) }
abort 'invalid bpg/proxmox version in Terraform lock file' unless locked_version&.match?(/^\s*version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"\s*$/)

File.foreach(File.join(tf_dir, 'main.tf')) do |line|
  next if line.match?(/^\s*(?:#|\/\/)/)
  match = line.match(/^\s*source\s*=\s*"([^"]+)"/)
  next unless match
  source = match[1]
  next if source.start_with?('./', '../')
  abort "remote module source is not allowed in main.tf: #{source}"
end
RUBY

terraform -chdir="$tf_dir" fmt -check -recursive
tf_data_dir="$(mktemp -d "${TMPDIR:-/tmp}/openchoreo-terraform.XXXXXX")"
trap 'rm -rf "$tf_data_dir"' EXIT
TF_DATA_DIR="$tf_data_dir" terraform -chdir="$tf_dir" init \
  -backend=false \
  -input=false \
  -lockfile=readonly
TF_DATA_DIR="$tf_data_dir" terraform -chdir="$tf_dir" validate

printf 'terraform static validation: PASS\n'
