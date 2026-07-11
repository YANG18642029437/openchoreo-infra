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

ruby - "$tf_dir" "$modules_dir" <<'RUBY'
tf_dir, modules_dir = ARGV
files = Dir.glob([File.join(tf_dir, '*.tf'), File.join(modules_dir, '**/*.tf')])

def blocks(source, type)
  matches = []
  header = /^\s*#{Regexp.escape(type)}(?:\s+"[^"]+")?\s*\{/
  offset = 0

  while (match = header.match(source, offset))
    opening = source.index('{', match.begin(0))
    depth = 1
    cursor = opening + 1
    while cursor < source.length && depth.positive?
      depth += 1 if source[cursor] == '{'
      depth -= 1 if source[cursor] == '}'
      cursor += 1
    end
    abort "unterminated #{type} block" unless depth.zero?
    matches << source[(opening + 1)...(cursor - 1)]
    offset = cursor
  end

  matches
end

versions_source = File.read(File.join(tf_dir, 'versions.tf'))
required_providers = blocks(versions_source, 'required_providers').first
abort 'missing required_providers block in versions.tf' unless required_providers

proxmox = required_providers[/\bproxmox\s*=\s*\{(.*?)\}/m, 1]
abort 'missing proxmox required provider declaration' unless proxmox
abort 'missing proxmox required provider version' unless proxmox.match?(/\bversion\s*=\s*"[^"]+"/)

floating = /\A(?:latest|main|master)\z/i
provider_version = proxmox[/\bversion\s*=\s*"([^"]+)"/, 1]
abort "floating proxmox provider version: #{provider_version}" if provider_version.match?(floating)

files.each do |file|
  blocks(File.read(file), 'module').each do |body|
    source = body[/\bsource\s*=\s*"([^"]+)"/, 1]
    next unless source
    next if source.start_with?('./', '../')

    if source.start_with?('git::')
      ref = source[/[?&]ref=([^&]+)/, 1]
      abort "unpinned git module source in #{file}: #{source}" unless ref
      abort "floating git module ref in #{file}: #{ref}" if ref.match?(floating)
    else
      version = body[/\bversion\s*=\s*"([^"]+)"/, 1]
      abort "missing module version in #{file}: #{source}" unless version
      abort "floating module version in #{file}: #{version}" if version.match?(floating)
    end
  end
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
