#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

load_targets() {
  local output
  output="$(ruby -ryaml -ripaddr -e '
    network = YAML.safe_load(File.read(ARGV.fetch(0)))
    hosts = YAML.safe_load(File.read(ARGV.fetch(1)))
    raise "network inventory is not a mapping" unless network.is_a?(Hash)
    raise "host inventory is not a mapping" unless hosts.is_a?(Hash)

    pool = network.fetch("metallb_pool")
    first = IPAddr.new(pool.fetch("start"))
    last = IPAddr.new(pool.fetch("end"))
    raise "MetalLB pool must be IPv4" unless first.ipv4? && last.ipv4?
    raise "invalid MetalLB pool bounds" if first.to_i > last.to_i

    values = (first.to_i..last.to_i).map { |value| IPAddr.new(value, Socket::AF_INET).to_s }
    values << IPAddr.new(network.fetch("kubernetes_api_vip")).to_s
    nfs = hosts.fetch("all").fetch("children").fetch("nfs_servers").fetch("hosts")
    values << IPAddr.new(nfs.fetch("nfs-storage-01").fetch("ansible_host")).to_s
    raise "empty IP audit target list" if values.empty?
    raise "duplicate IP audit target" unless values.uniq.length == values.length
    puts values
  ' "$repo_root/inventory/network.yaml" "$repo_root/inventory/hosts.yaml")"

  targets=()
  while IFS= read -r target; do
    [ -n "$target" ] && targets+=("$target")
  done <<< "$output"
  [ "${#targets[@]}" -gt 0 ] || die 'empty IP audit target list'
}

configure_platform() {
  if [ "$#" -ne 1 ]; then
    die 'usage: configure_platform <platform>'
  fi

  platform="$1"
  case "$platform" in
    Darwin)
      require_command route
      ping_args=(-c 1 -W 1000)
      route_args=(route -n get)
      ;;
    Linux)
      require_command ip
      ping_args=(-c 1 -W 1)
      route_args=(ip route get)
      ;;
    *) die "unsupported platform: $platform" ;;
  esac
}

record_no_response() {
  printf 'NO_RESPONSE %s\n' "$1"
  no_response_count=$((no_response_count + 1))
}

check_arp_cache() {
  local target="$1"
  local arp_output arp_status entry rg_status

  set +e
  arp_output="$(arp -an 2>&1)"
  arp_status=$?
  set -e
  if [ "$arp_status" -ne 0 ]; then
    printf 'ERROR arp %s rc=%s\n' "$target" "$arp_status" >&2
    error_count=$((error_count + 1))
    return
  fi

  set +e
  entry="$(printf '%s\n' "$arp_output" | rg -F "($target)")"
  rg_status=$?
  set -e
  case "$rg_status" in
    0)
      if [[ "$entry" =~ [Ii][Nn][Cc][Oo][Mm][Pp][Ll][Ee][Tt][Ee] ]]; then
        record_no_response "$target"
      elif [[ "$entry" =~ [[:xdigit:]]{2}(:[[:xdigit:]]{2}){5} ]]; then
        printf 'BUSY arp_cache %s\n' "$target"
        busy_count=$((busy_count + 1))
      else
        record_no_response "$target"
      fi
      ;;
    1) record_no_response "$target" ;;
    *)
      printf 'ERROR arp_match %s rc=%s\n' "$target" "$rg_status" >&2
      error_count=$((error_count + 1))
      ;;
  esac
}

audit_target() {
  local target="$1"
  local route_output route_status ping_status

  set +e
  route_output="$("${route_args[@]}" "$target" 2>&1)"
  route_status=$?
  set -e
  if [ "$route_status" -ne 0 ]; then
    printf 'ERROR route %s rc=%s\n' "$target" "$route_status" >&2
    error_count=$((error_count + 1))
    return
  fi
  printf 'ROUTE %s\n%s\n' "$target" "$route_output"

  set +e
  ping "${ping_args[@]}" "$target" >/dev/null 2>&1
  ping_status=$?
  set -e
  case "$ping_status" in
    0)
      printf 'BUSY ping %s\n' "$target"
      busy_count=$((busy_count + 1))
      ;;
    1) check_arp_cache "$target" ;;
    *)
      printf 'ERROR ping %s rc=%s\n' "$target" "$ping_status" >&2
      error_count=$((error_count + 1))
      ;;
  esac
}

main() {
  require_command ruby
  load_targets

  if [ "${IP_AUDIT_DRY_RUN:-0}" = 1 ]; then
    printf 'audit_mode: dry_run\n'
    for target in "${targets[@]}"; do
      printf 'audit_target: %s\n' "$target"
    done
    return 0
  fi

  require_command ping
  require_command arp
  require_command rg
  require_command uname
  configure_platform "$(uname -s)"

  busy_count=0
  no_response_count=0
  error_count=0
  printf 'audit_started_at: %s\n' "$(timestamp)"
  printf 'audit_platform: %s\n' "$platform"
  for target in "${targets[@]}"; do
    audit_target "$target"
  done
  printf 'SUMMARY busy=%s no_response=%s errors=%s\n' \
    "$busy_count" "$no_response_count" "$error_count"

  if [ "$error_count" -gt 0 ]; then
    return 2
  fi
  if [ "$busy_count" -gt 0 ]; then
    return 1
  fi
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
