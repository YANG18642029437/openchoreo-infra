#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/proxmox-api.sh"

remaining_seconds() {
  local deadline="$1"
  local now
  now="$(date -u '+%s')"
  printf '%s\n' "$((deadline - now))"
}

bounded_request_timeout() {
  local deadline="$1"
  local request_timeout="$2"
  local remaining
  remaining="$(remaining_seconds "$deadline")"
  [ "$remaining" -gt 0 ] || proxmox_api_die 'destructive Proxmox task reached its deadline'
  if [ "$remaining" -lt "$request_timeout" ]; then
    printf '%s\n' "$remaining"
  else
    printf '%s\n' "$request_timeout"
  fi
}

wait_for_task() {
  local node="$1"
  local upid="$2"
  local deadline="$3"
  local request_timeout="$4"
  local poll_interval="$5"
  local encoded_upid response status_line status exitstatus per_request remaining
  encoded_upid="$(proxmox_api_urlencode "$upid")"

  while :; do
    per_request="$(bounded_request_timeout "$deadline" "$request_timeout")"
    response="$(PROXMOX_API_REQUEST_TIMEOUT_SECONDS="$per_request" \
      proxmox_api_get "/nodes/${node}/tasks/${encoded_upid}/status")"
    [ "$(remaining_seconds "$deadline")" -gt 0 ] || proxmox_api_die 'destructive Proxmox task reached its deadline'
    status_line="$(printf '%s' "$response" | proxmox_api_json_task_status)"
    IFS=$'\t' read -r status exitstatus <<<"$status_line"
    if [ "$status" = stopped ]; then
      [ "$exitstatus" = OK ] || proxmox_api_die "Proxmox task failed: ${exitstatus:-unknown}"
      return
    fi
    remaining="$(remaining_seconds "$deadline")"
    [ "$poll_interval" -lt "$remaining" ] || proxmox_api_die 'destructive Proxmox task reached its deadline'
    [ "$poll_interval" -eq 0 ] || sleep "$poll_interval"
  done
}

wait_for_vm_stopped() {
  local node="$1"
  local vmid="$2"
  local deadline="$3"
  local request_timeout="$4"
  local poll_interval="$5"
  local response status per_request remaining

  while :; do
    per_request="$(bounded_request_timeout "$deadline" "$request_timeout")"
    response="$(PROXMOX_API_REQUEST_TIMEOUT_SECONDS="$per_request" \
      proxmox_api_get "/nodes/${node}/qemu/${vmid}/status/current")"
    [ "$(remaining_seconds "$deadline")" -gt 0 ] || proxmox_api_die "stop deadline reached for VM ${vmid}"
    status="$(printf '%s' "$response" | proxmox_api_json_vm_status)"
    [ "$status" = stopped ] && return
    remaining="$(remaining_seconds "$deadline")"
    [ "$poll_interval" -lt "$remaining" ] || proxmox_api_die "stop deadline reached for VM ${vmid}"
    [ "$poll_interval" -eq 0 ] || sleep "$poll_interval"
  done
}

validated_vm_ids() {
  local vmids="$1"
  local vmid csv=''
  for vmid in $vmids; do
    [[ "$vmid" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'invalid VM ID in PVE_REMOVE_VM_IDS'
    if [ -n "$csv" ]; then
      csv+=','
    fi
    csv+="$vmid"
  done
  [ -n "$csv" ] || proxmox_api_die 'PVE_REMOVE_VM_IDS must not be empty'
  printf '%s\n' "$csv"
}

main() {
  local node="${PVE_REMOVE_NODE:-pve2162}"
  local vmids='120 121 122'
  local expected_confirmation
  expected_confirmation="$(validated_vm_ids "$vmids")"

  if [ -n "${PVE_REMOVE_VM_IDS+x}" ] && [ "$PVE_REMOVE_VM_IDS" != "$vmids" ]; then
    proxmox_api_die 'PVE_REMOVE_VM_IDS cannot change the canonical VM allowlist 120 121 122'
  fi
  [ "${ALLOW_DESTRUCTIVE_REBUILD:-}" = CONFIRMED_BY_USER ] ||
    proxmox_api_die 'ALLOW_DESTRUCTIVE_REBUILD must equal CONFIRMED_BY_USER'
  [ "${CONFIRM_VM_IDS:-}" = "$expected_confirmation" ] ||
    proxmox_api_die "CONFIRM_VM_IDS must exactly equal ${expected_confirmation}"
  : "${PVE_BACKUP_MANIFEST:?PVE_BACKUP_MANIFEST must identify the verified backup run}"
  [ -f "$PVE_BACKUP_MANIFEST" ] || proxmox_api_die "backup manifest not found: ${PVE_BACKUP_MANIFEST}"
  [[ "$node" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe removal node name'

  PROXMOX_BACKUP_NODE="$node" PROXMOX_BACKUP_VMIDS="$vmids" \
    "$repo_root/scripts/verify/proxmox-backups.sh"
  proxmox_api_init

  local task_timeout="${PVE_REMOVE_TASK_TIMEOUT_SECONDS:-300}"
  local request_timeout="${PROXMOX_VE_REQUEST_TIMEOUT:-60}"
  local poll_interval="${PVE_REMOVE_POLL_INTERVAL:-2}"
  [[ "$task_timeout" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'removal task timeout must be a positive integer'
  [[ "$request_timeout" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'request timeout must be a positive integer'
  [[ "$poll_interval" =~ ^[0-9]+$ ]] || proxmox_api_die 'removal poll interval must be a non-negative integer'

  local vmid response status upid deadline per_request response_with_status http_status response_body
  for vmid in $vmids; do
    response_with_status="$(proxmox_api_get_with_status "/nodes/${node}/qemu/${vmid}/status/current")"
    http_status="${response_with_status%%$'\n'*}"
    response_body="${response_with_status#*$'\n'}"
    if [ "$http_status" = 404 ]; then
      printf 'REMOVE_ALREADY_ABSENT vmid=%s\n' "$vmid"
      continue
    fi
    [ "$http_status" = 200 ] || proxmox_api_die "VM status request failed for VM ${vmid} with HTTP ${http_status}"
    response="$response_body"
    status="$(printf '%s' "$response" | proxmox_api_json_vm_status)"
    if [ "$status" = running ]; then
      deadline=$(($(date -u '+%s') + task_timeout))
      per_request="$(bounded_request_timeout "$deadline" "$request_timeout")"
      response="$(PROXMOX_API_REQUEST_TIMEOUT_SECONDS="$per_request" \
        proxmox_api_post "/nodes/${node}/qemu/${vmid}/status/stop")"
      [ "$(remaining_seconds "$deadline")" -gt 0 ] || proxmox_api_die "stop request deadline reached for VM ${vmid}"
      upid="$(printf '%s' "$response" | proxmox_api_json_data_string)"
      [[ "$upid" =~ ^UPID:[A-Za-z0-9._-]+:[[:graph:]]+$ ]] || proxmox_api_die "invalid stop UPID for VM ${vmid}"
      wait_for_task "$node" "$upid" "$deadline" "$request_timeout" "$poll_interval"
      wait_for_vm_stopped "$node" "$vmid" "$deadline" "$request_timeout" "$poll_interval"
    fi

    deadline=$(($(date -u '+%s') + task_timeout))
    per_request="$(bounded_request_timeout "$deadline" "$request_timeout")"
    response="$(PROXMOX_API_REQUEST_TIMEOUT_SECONDS="$per_request" \
      proxmox_api_delete "/nodes/${node}/qemu/${vmid}/config" \
      purge 1 destroy-unreferenced-disks 1)"
    [ "$(remaining_seconds "$deadline")" -gt 0 ] || proxmox_api_die "delete request deadline reached for VM ${vmid}"
    upid="$(printf '%s' "$response" | proxmox_api_json_data_string)"
    [[ "$upid" =~ ^UPID:[A-Za-z0-9._-]+:[[:graph:]]+$ ]] || proxmox_api_die "invalid delete UPID for VM ${vmid}"
    wait_for_task "$node" "$upid" "$deadline" "$request_timeout" "$poll_interval"
    printf 'REMOVE_OK vmid=%s\n' "$vmid"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
