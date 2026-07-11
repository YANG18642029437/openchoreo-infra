#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/proxmox-api.sh"

main() {
  proxmox_api_init

  local node="${PROXMOX_BACKUP_NODE:-pve2162}"
  local storage="${PROXMOX_BACKUP_STORAGE:-PvEDump}"
  local vmids="${PROXMOX_BACKUP_VMIDS:-120 121 122}"
  local poll_interval="${PROXMOX_BACKUP_POLL_INTERVAL:-2}"
  local task_timeout="${PVE_TASK_TIMEOUT_SECONDS:-1800}"
  local request_timeout="${PROXMOX_VE_REQUEST_TIMEOUT:-60}"
  local manifest="${PROXMOX_BACKUP_MANIFEST:-$repo_root/.private/backups/proxmox-vzdump-manifest.tsv}"
  local manifest_dir manifest_tmp=''
  local note_time
  note_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  [[ "$node" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup node name'
  [[ "$storage" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup storage name'
  [[ "$poll_interval" =~ ^[0-9]+$ ]] || proxmox_api_die 'backup poll interval must be a non-negative integer'
  [[ "$task_timeout" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'task timeout must be a positive integer'
  [[ "$request_timeout" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'request timeout must be a positive integer'

  manifest_dir="$(dirname "$manifest")"
  umask 077
  mkdir -p "$manifest_dir"
  chmod 700 "$manifest_dir"
  manifest_tmp="$(mktemp "${manifest}.tmp.XXXXXX")"
  chmod 600 "$manifest_tmp"
  trap 'if [ -n "${manifest_tmp:-}" ]; then rm -f -- "$manifest_tmp"; fi' EXIT
  printf 'vmid\tstart_epoch\tupid\n' >"$manifest_tmp"

  local vmid
  for vmid in $vmids; do
    [[ "$vmid" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'invalid VM ID in PROXMOX_BACKUP_VMIDS'

    local response upid encoded_upid status_line status exitstatus start_epoch deadline now remaining per_request_timeout
    start_epoch="$(date -u '+%s')"
    deadline=$((start_epoch + task_timeout))
    response="$(proxmox_api_post "/nodes/${node}/vzdump" \
      vmid "$vmid" \
      storage "$storage" \
      mode snapshot \
      compress zstd \
      remove 0 \
      notes-template "OpenChoreo API backup ${note_time}")"
    upid="$(printf '%s' "$response" | proxmox_api_json_data_string)"
    case "$upid" in
      *$'\t'* | *$'\n'* | *$'\r'*) proxmox_api_die "backup task returned an unsafe UPID for VM ${vmid}" ;;
    esac
    encoded_upid="$(proxmox_api_urlencode "$upid")"

    status=''
    exitstatus=''
    while :; do
      now="$(date -u '+%s')"
      remaining=$((deadline - now))
      [ "$remaining" -gt 0 ] || proxmox_api_die "backup task timed out for VM ${vmid}"
      per_request_timeout="$request_timeout"
      if [ "$remaining" -lt "$per_request_timeout" ]; then
        per_request_timeout="$remaining"
      fi
      status_line="$(PROXMOX_API_REQUEST_TIMEOUT_SECONDS="$per_request_timeout" \
        proxmox_api_get "/nodes/${node}/tasks/${encoded_upid}/status" | proxmox_api_json_task_status)"
      now="$(date -u '+%s')"
      [ "$now" -lt "$deadline" ] || proxmox_api_die "backup task timed out for VM ${vmid}"
      IFS=$'\t' read -r status exitstatus <<<"$status_line"
      if [ "$status" = stopped ]; then
        break
      fi
      remaining=$((deadline - now))
      if [ "$poll_interval" -gt 0 ]; then
        [ "$poll_interval" -lt "$remaining" ] || proxmox_api_die "backup task timed out for VM ${vmid}"
        sleep "$poll_interval"
      fi
    done

    [ "$exitstatus" = OK ] || proxmox_api_die "backup task failed for VM ${vmid}: ${exitstatus:-unknown}"
    printf '%s\t%s\t%s\n' "$vmid" "$start_epoch" "$upid" >>"$manifest_tmp"
    printf 'BACKUP_TASK_OK vmid=%s\n' "$vmid"
  done

  mv -f -- "$manifest_tmp" "$manifest"
  manifest_tmp=''
  chmod 600 "$manifest"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
