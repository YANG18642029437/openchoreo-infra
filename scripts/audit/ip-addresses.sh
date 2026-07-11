#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

print_error_summary() {
  printf 'SUMMARY busy=0 no_response=0 errors=1\n'
}

require_audit_command() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    printf 'ERROR audit usage: require_audit_command <command>\n' >&2
    return 2
  fi
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR audit missing command: %s\n' "$1" >&2
    return 2
  fi
}

load_targets() {
  local output ruby_status
  set +e
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
  ' "$repo_root/inventory/network.yaml" "$repo_root/inventory/hosts.yaml" 2>&1)"
  ruby_status=$?
  set -e
  if [ "$ruby_status" -ne 0 ]; then
    printf 'ERROR inventory %s\n' "$output" >&2
    return 2
  fi

  targets=()
  while IFS= read -r target; do
    [ -n "$target" ] && targets+=("$target")
  done <<< "$output"
  if [ "${#targets[@]}" -eq 0 ]; then
    printf 'ERROR inventory empty IP audit target list\n' >&2
    return 2
  fi
}

configure_platform() {
  if [ "$#" -ne 1 ]; then
    printf 'ERROR audit usage: configure_platform <platform>\n' >&2
    return 2
  fi

  platform="$1"
  case "$platform" in
    Darwin)
      require_audit_command route || return 2
      require_audit_command arp || return 2
      ping_args=(-c 1 -W 1000)
      ping_no_reply_status=2
      route_args=(route -n get)
      neighbor_args=(arp -an)
      neighbor_mode=Darwin
      ;;
    Linux)
      require_audit_command ip || return 2
      ping_args=(-c 1 -W 1)
      ping_no_reply_status=1
      route_args=(ip route get)
      neighbor_args=(ip neigh show)
      neighbor_mode=Linux
      ;;
    *)
      printf 'ERROR audit unsupported platform: %s\n' "$platform" >&2
      return 2
      ;;
  esac
}

record_no_response() {
  printf 'NO_RESPONSE %s\n' "$1"
  no_response_count=$((no_response_count + 1))
}

check_neighbor_cache() {
  local target="$1"
  local neighbor_output neighbor_status entry rg_status target_pattern

  set +e
  neighbor_output="$("${neighbor_args[@]}" 2>&1)"
  neighbor_status=$?
  set -e
  if [ "$neighbor_status" -ne 0 ]; then
    printf 'ERROR neighbor %s rc=%s\n' "$target" "$neighbor_status" >&2
    error_count=$((error_count + 1))
    return
  fi

  set +e
  if [ "$neighbor_mode" = Darwin ]; then
    entry="$(printf '%s\n' "$neighbor_output" | rg -F "($target)")"
  else
    target_pattern="${target//./\\.}"
    entry="$(printf '%s\n' "$neighbor_output" | rg -e "^${target_pattern}([[:space:]]|$)")"
  fi
  rg_status=$?
  set -e
  case "$rg_status" in
    0)
      if [[ "$entry" =~ [Ii][Nn][Cc][Oo][Mm][Pp][Ll][Ee][Tt][Ee] ]] ||
        [[ "$entry" =~ [Ff][Aa][Ii][Ll][Ee][Dd] ]]; then
        record_no_response "$target"
      elif [[ "$entry" =~ [[:xdigit:]]{2}(:[[:xdigit:]]{2}){5} ]] &&
        { [ "$neighbor_mode" = Darwin ] || [[ "$entry" =~ [[:space:]]lladdr[[:space:]] ]]; }; then
        printf 'BUSY neighbor_cache %s\n' "$target"
        busy_count=$((busy_count + 1))
      else
        record_no_response "$target"
      fi
      ;;
    1) record_no_response "$target" ;;
    *)
      printf 'ERROR neighbor_match %s rc=%s\n' "$target" "$rg_status" >&2
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
    *)
      if [ "$ping_status" -eq "$ping_no_reply_status" ]; then
        check_neighbor_cache "$target"
      else
        printf 'ERROR ping %s rc=%s\n' "$target" "$ping_status" >&2
        error_count=$((error_count + 1))
      fi
      ;;
  esac
}

main() {
  if ! require_audit_command ruby; then
    print_error_summary
    return 2
  fi
  if ! load_targets; then
    print_error_summary
    return 2
  fi

  if [ "${IP_AUDIT_DRY_RUN:-0}" = 1 ]; then
    printf 'audit_mode: dry_run\n'
    for target in "${targets[@]}"; do
      printf 'audit_target: %s\n' "$target"
    done
    return 0
  fi

  if ! require_audit_command ping || ! require_audit_command rg ||
    ! require_audit_command uname; then
    print_error_summary
    return 2
  fi
  local detected_platform uname_status
  set +e
  detected_platform="$(uname -s 2>&1)"
  uname_status=$?
  set -e
  if [ "$uname_status" -ne 0 ]; then
    printf 'ERROR audit uname rc=%s\n' "$uname_status" >&2
    print_error_summary
    return 2
  fi
  if ! configure_platform "$detected_platform"; then
    print_error_summary
    return 2
  fi

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
