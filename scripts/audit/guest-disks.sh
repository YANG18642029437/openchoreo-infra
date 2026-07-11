#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

device=/dev/sdb

audit_error() {
  printf 'ERROR audit %s\n' "$1" >&2
  printf 'SUMMARY hosts=0 errors=1\n'
  return 2
}

load_hosts() {
  local output status
  set +e
  output="$(ruby -ryaml -e '
    inventory = YAML.safe_load(File.read(ARGV.fetch(0)))
    hosts = inventory.fetch("all").fetch("children").fetch("k3s_servers").fetch("hosts")
    values = hosts.values.map { |entry| entry.fetch("ansible_host") }
    raise "empty guest audit host list" if values.empty?
    raise "duplicate guest audit host" unless values.uniq.length == values.length
    values.each do |value|
      parts = value.to_s.split(".", -1)
      valid = parts.length == 4 && parts.all? { |part| part.match?(/\A(?:0|[1-9][0-9]{0,2})\z/) && part.to_i <= 255 }
      raise "invalid IPv4 address: #{value}" unless valid
    end
    puts values
  ' "$repo_root/inventory/hosts.yaml" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    printf 'ERROR inventory %s\n' "$output" >&2
    return 2
  fi
  hosts=()
  while IFS= read -r host; do
    [ -n "$host" ] && hosts+=("$host")
  done <<< "$output"
  [ "${#hosts[@]}" -gt 0 ] || return 2
}

validate_user() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    printf 'ERROR audit invalid SSH user\n' >&2
    return 2
  fi
  if ! [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
    printf 'ERROR audit unsafe SSH user: %s\n' "$1" >&2
    return 2
  fi
}

validate_host() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ] || [[ "$1" = -* ]] ||
    ! [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    printf 'ERROR audit unsafe SSH host: %s\n' "${1:-}" >&2
    return 2
  fi
}

build_ssh_args() {
  local destination="$1"
  ssh_args=(
    ssh -F /dev/null
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=1
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=yes
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
  )
  if [ -n "${GUEST_AUDIT_SSH_IDENTITY_FILE:-}" ]; then
    require_file "$GUEST_AUDIT_SSH_IDENTITY_FILE"
    ssh_args+=(-i "$GUEST_AUDIT_SSH_IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi
  ssh_args+=(-- "$destination")
}

audit_host() {
  local host="$1" destination="$ssh_user@$host" ssh_status
  validate_host "$host" || return 2
  build_ssh_args "$destination"
  printf 'audit_started_at: %s\n' "$(timestamp)"
  printf 'audit_target: %s\n' "$destination"
  printf 'audit_device: %s\n' "$device"
  set +e
  "${ssh_args[@]}" '
    set -eu
    device=/dev/sdb
    printf "%s\n" "=== host ==="
    hostname
    printf "%s\n" "=== block_devices ==="
    lsblk --json --output NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID
    printf "%s\n" "=== mounts ==="
    findmnt --json
    printf "%s\n" "=== target_device ==="
    if ! test -b "$device"; then
      printf "ERROR missing block device %s\n" "$device" >&2
      exit 1
    fi
    if ! command -v wipefs >/dev/null 2>&1; then
      printf "%s\n" "ERROR missing command: wipefs" >&2
      exit 1
    fi
    wipefs --no-act --all "$device"
    printf "%s\n" "=== blkid ==="
    if blkid_output="$(blkid "$device" 2>&1)"; then
      printf "%s\n" "$blkid_output"
    else
      blkid_status=$?
      if [ "$blkid_status" -eq 2 ]; then
        printf "NO_BLKID_SIGNATURE %s\n" "$device"
      else
        printf "ERROR blkid %s rc=%s\n" "$device" "$blkid_status" >&2
        exit "$blkid_status"
      fi
    fi
  ' 2>&1 | redact
  ssh_status=$?
  set -e
  return "$ssh_status"
}

main() {
  local ssh_user="${GUEST_AUDIT_SSH_USER-root}"
  if ! command -v ruby >/dev/null 2>&1; then
    audit_error 'missing command: ruby'
    return 2
  fi
  if ! load_hosts; then
    printf 'SUMMARY hosts=0 errors=1\n'
    return 2
  fi
  if ! validate_user "$ssh_user"; then
    printf 'SUMMARY hosts=0 errors=1\n'
    return 2
  fi
  if [ -n "${GUEST_AUDIT_SSH_IDENTITY_FILE:-}" ] &&
    [ ! -f "$GUEST_AUDIT_SSH_IDENTITY_FILE" ]; then
    audit_error "missing identity file: $GUEST_AUDIT_SSH_IDENTITY_FILE"
    return 2
  fi

  if [ "${GUEST_AUDIT_DRY_RUN:-0}" = 1 ]; then
    printf 'audit_mode: dry_run\n'
    for host in "${hosts[@]}"; do
      validate_host "$host" || return 2
      printf 'audit_target: %s@%s\n' "$ssh_user" "$host"
      printf 'audit_device: %s\n' "$device"
    done
    return 0
  fi

  if ! command -v ssh >/dev/null 2>&1; then
    audit_error 'missing command: ssh'
    return 2
  fi
  error_count=0
  for host in "${hosts[@]}"; do
    if ! audit_host "$host"; then
      error_count=$((error_count + 1))
    fi
  done
  printf 'SUMMARY hosts=%s errors=%s\n' "${#hosts[@]}" "$error_count"
  [ "$error_count" -eq 0 ] || return 2
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
