#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version_lock="$repo_root/versions.lock.yaml"

if [ ! -f "$version_lock" ]; then
  printf 'missing version lock: %s\n' "$version_lock" >&2
  exit 1
fi

yaml_value() {
  requested_path="$1"

  if command -v yq >/dev/null 2>&1; then
    if ! value="$(yq -r "$requested_path" "$version_lock")"; then
      printf 'failed to read version lock path with yq: %s\n' "$requested_path" >&2
      return 1
    fi
    printf '%s' "$value"
    return 0
  fi

  if [ -x /usr/bin/ruby ]; then
    /usr/bin/ruby -ryaml -e '
      begin
        lock_file = ARGV.fetch(0)
        requested_path = ARGV.fetch(1)
        document = YAML.safe_load(
          File.read(lock_file),
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        value = requested_path.split(".").reject(&:empty?).reduce(document) do |node, key|
          node.is_a?(Hash) && node.key?(key) ? node[key] : nil
        end

        case value
        when nil
          print "null"
        when String, Numeric, TrueClass, FalseClass
          print value.to_s
        else
          warn "version lock value is not scalar: #{requested_path}"
          exit 1
        end
      rescue StandardError => error
        warn "failed to read version lock: #{error.message}"
        exit 1
      end
    ' "$version_lock" "$requested_path"
    return
  fi

  printf 'version lock verification requires yq or /usr/bin/ruby\n' >&2
  return 1
}

required_paths=(
  .terraform.cli
  .terraform.proxmox_provider
  .kubernetes.k3s
  .kubernetes.cilium
  .kubernetes.argocd_chart
  .platform.openchoreo
  .platform.harbor_chart
  .platform.crossplane
  .platform.cloudnative_pg
)

for path in "${required_paths[@]}"; do
  value="$(yaml_value "$path")"

  if [ -z "$value" ] || [ "$value" = null ]; then
    printf 'missing locked version: %s\n' "$path" >&2
    exit 1
  fi

  case "$value" in
    latest|main|master|nightly|dev)
      printf 'unlocked version: %s=%s\n' "$path" "$value" >&2
      exit 1
      ;;
  esac
done

printf 'version lock: PASS\n'
