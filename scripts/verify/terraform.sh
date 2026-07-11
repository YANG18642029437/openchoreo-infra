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

def active_lines(path)
  lines = []
  heredoc_end = nil
  block_comment = false

  File.foreach(path) do |raw|
    if heredoc_end
      heredoc_end = nil if raw.strip == heredoc_end
      next
    end

    code = +''
    quoted = false
    escaped = false
    index = 0
    while index < raw.length
      pair = raw[index, 2]
      if block_comment
        if pair == '*/'
          block_comment = false
          index += 2
        else
          index += 1
        end
      elsif !quoted && pair == '/*'
        block_comment = true
        index += 2
      elsif !quoted && (raw[index] == '#' || pair == '//')
        break
      else
        character = raw[index]
        code << character
        if quoted
          if escaped
            escaped = false
          elsif character == '\\'
            escaped = true
          elsif character == '"'
            quoted = false
          end
        elsif character == '"'
          quoted = true
        end
        index += 1
      end
    end

    stripped = code.strip
    next if stripped.empty?
    if (match = stripped.match(/<<-?([A-Za-z_][A-Za-z0-9_]*)/))
      heredoc_end = match[1]
    end
    lines << stripped
  end

  lines
end

version_lines = active_lines(File.join(tf_dir, 'versions.tf'))
proxmox_index = version_lines.index { |line| line.match?(/\Aproxmox\s*=\s*\{\z/) }
abort 'missing proxmox required provider declaration' unless proxmox_index
proxmox_lines = version_lines[(proxmox_index + 1)..].take_while { |line| line != '}' }
source = proxmox_lines.find { |line| line.match?(/\Asource\s*=/) }
abort 'invalid proxmox required provider source' unless source&.match?(/\Asource\s*=\s*"bpg\/proxmox"\z/)
version = proxmox_lines.find { |line| line.match?(/\Aversion\s*=/) }
exact_version = /\Aversion\s*=\s*"=\s*[0-9]+\.[0-9]+\.[0-9]+"\z/
abort 'proxmox provider version must use an exact constraint: = x.y.z' unless version&.match?(exact_version)

files.each do |file|
  lines = active_lines(file)
  lines.each_index.select { |index| lines[index].match?(/\Amodule\s+"[^"]+"\s*\{\z/) }.each do |index|
    source_line = lines[(index + 1)..].find { |line| line.match?(/\Asource\s*=/) }
    next unless source_line
    source = source_line[/\Asource\s*=\s*"([^"]+)"\z/, 1]
    abort "module source must be a literal repository-relative path in #{file}" unless source
    next if source.start_with?('./', '../')
    abort "remote module source is not allowed in #{file}: #{source}"
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
