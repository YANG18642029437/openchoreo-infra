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
    if ! value="$(yq -e -r "$requested_path | select(tag == \"!!str\")" "$version_lock")"; then
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

        if value.is_a?(String)
          print value
        else
          warn "version lock value is not a scalar string: #{requested_path}"
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
  .operating_system.ubuntu_release
  .operating_system.cloud_image_url
  .kubernetes.k3s
  .kubernetes.cilium
  .kubernetes.kube_vip
  .kubernetes.argocd_chart
  .kubernetes.argocd_app
  .kubernetes.metallb_chart
  .kubernetes.ingress_nginx_chart
  .kubernetes.nfs_csi
  .openchoreo_compatibility.gateway_api
  .openchoreo_compatibility.cert_manager
  .openchoreo_compatibility.external_secrets
  .openchoreo_compatibility.kgateway
  .openchoreo_compatibility.openbao_chart
  .openchoreo_compatibility.openbao_app
  .platform.openchoreo
  .platform.harbor_chart
  .platform.harbor_app
  .platform.observability_logs
  .platform.observability_traces
  .platform.observability_metrics
  .platform.crossplane
  .platform.cloudnative_pg
)

for path in "${required_paths[@]}"; do
  value="$(yaml_value "$path")"

  if [ -z "$value" ] || [ "$value" = null ]; then
    printf 'missing locked version: %s\n' "$path" >&2
    exit 1
  fi

  trimmed_value="$value"
  while :; do
    case "$trimmed_value" in
      [[:space:]]*) trimmed_value="${trimmed_value#?}" ;;
      *[[:space:]]) trimmed_value="${trimmed_value%?}" ;;
      *) break ;;
    esac
  done
  normalized_value="$(printf '%s' "$trimmed_value" | LC_ALL=C tr '[:upper:]' '[:lower:]')"

  case "$normalized_value" in
    latest|main|master|nightly|dev)
      printf 'unlocked version: %s=%s\n' "$path" "$value" >&2
      exit 1
      ;;
  esac

  if [ "$value" != "$trimmed_value" ]; then
    printf 'version has surrounding whitespace: %s=%s\n' "$path" "$value" >&2
    exit 1
  fi
done

printf 'version lock: PASS\n'
