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

terraform -chdir="$tf_dir" fmt -check -recursive

ruby - "$tf_dir" "$modules_dir" <<'RUBY'
tf_dir, modules_dir = ARGV
version_files = [File.join(tf_dir, 'versions.tf')]
version_files.concat(Dir.glob(File.join(modules_dir, '**/versions.tf')))
version_files.each do |file|
  File.foreach(file) do |line|
    next if line.match?(/^\s*(?:#|\/\/)/)
    abort "module declarations are not allowed in #{file}" if line.match?(/^\s*module\s+"/)
  end
end

lock_lines = File.readlines(File.join(tf_dir, '.terraform.lock.hcl'))
provider_index = lock_lines.index { |line| line.match?(/^provider\s+"registry\.terraform\.io\/bpg\/proxmox"\s*\{\s*$/) }
abort 'missing bpg/proxmox provider in Terraform lock file' unless provider_index
locked_version = lock_lines[(provider_index + 1)..].find { |line| line.match?(/^\s*version\s*=/) }
abort 'invalid bpg/proxmox version in Terraform lock file' unless locked_version&.match?(/^\s*version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"\s*$/)

files = Dir.glob(File.join(tf_dir, '*.tf'))
files.concat(Dir.glob(File.join(modules_dir, '**/*.tf')))
files.reject! { |file| File.basename(file) == 'versions.tf' }
files.each do |file|
  File.foreach(file) do |line|
    next if line.match?(/^\s*(?:#|\/\/)/)
    match = line.match(/^\s*source\s*=\s*"([^"]+)"/)
    next unless match
    source = match[1]
    next if source.start_with?('./', '../')
    abort "remote module source is not allowed in #{file}: #{source}"
  end
end

main = File.read(File.join(tf_dir, 'main.tf'))
variables = File.read(File.join(tf_dir, 'variables.tf'))
abort 'PVE 8.2 must not use the unsupported import download resource' if main.include?('proxmox_virtual_environment_download_file')
abort 'VM9000 must be treated as an external template' if main.include?('resource "proxmox_virtual_environment_vm" "ubuntu_template"')
abort 'missing external template_vm_id variable' unless variables.match?(/variable\s+"template_vm_id"/)
abort 'K3s clones must use var.template_vm_id' unless main.match?(/module\s+"k3s_nodes".*?template_vm_id\s*=\s*var\.template_vm_id/m)
abort 'NFS clone must use var.template_vm_id' unless main.match?(/module\s+"nfs_server".*?template_vm_id\s*=\s*var\.template_vm_id/m)
abort 'missing Terraform-managed egress gateway' unless main.match?(/module\s+"egress_gateway"/)
abort 'egress gateway must use var.template_vm_id' unless main.match?(/module\s+"egress_gateway".*?template_vm_id\s*=\s*var\.template_vm_id/m)
RUBY

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/openchoreo-terraform.XXXXXX")"
tf_data_dir="$temporary_dir/data"
provider_config_dir="$temporary_dir/provider-config"
mkdir -p "$tf_data_dir" "$provider_config_dir"
cp "$tf_dir/versions.tf" "$provider_config_dir/versions.tf"
trap 'rm -rf "$temporary_dir"' EXIT
TF_DATA_DIR="$tf_data_dir" terraform -chdir="$tf_dir" init \
  -backend=false \
  -input=false \
  -lockfile=readonly
TF_DATA_DIR="$tf_data_dir" terraform -chdir="$tf_dir" validate
providers_output="$(TF_DATA_DIR="$tf_data_dir" terraform -chdir="$provider_config_dir" providers)"
root_providers="$(printf '%s\n' "$providers_output" | awk '
  /^Providers required by configuration:$/ { in_configuration = 1; next }
  in_configuration && /^\.$/ { in_root = 1; next }
  in_root && /module\./ { exit }
  in_root { print }
')"
if ! printf '%s\n' "$root_providers" | grep -Eq \
  'provider\[registry\.terraform\.io/bpg/proxmox\][[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$'; then
  printf 'proxmox provider must use an exact semantic version constraint\n' >&2
  exit 1
fi

printf 'terraform static validation: PASS\n'
