#!/usr/bin/env bash
# Sourcing this library intentionally enables errexit, nounset, and pipefail.
set -euo pipefail

proxmox_api_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

proxmox_api_init() {
  : "${PROXMOX_VE_ENDPOINT:?PROXMOX_VE_ENDPOINT must be exported}"
  : "${PROXMOX_VE_API_TOKEN:?PROXMOX_VE_API_TOKEN must be exported}"

  command -v curl >/dev/null 2>&1 || proxmox_api_die 'missing command: curl'
  command -v python3 >/dev/null 2>&1 || proxmox_api_die 'missing command: python3'

  PROXMOX_API_BASE="${PROXMOX_VE_ENDPOINT%/}/api2/json"
  case "$PROXMOX_API_BASE" in
    https://*) ;;
    *) proxmox_api_die 'PROXMOX_VE_ENDPOINT must use https://' ;;
  esac
  case "$PROXMOX_API_BASE" in
    *'?'* | *'#'* | *$'\n'* | *$'\r'*) proxmox_api_die 'unsafe PROXMOX_VE_ENDPOINT' ;;
  esac
  case "$PROXMOX_VE_API_TOKEN" in
    *$'\n'* | *$'\r'*) proxmox_api_die 'unsafe PROXMOX_VE_API_TOKEN' ;;
  esac
  [[ "$PROXMOX_VE_API_TOKEN" =~ ^[[:graph:]]+$ ]] || proxmox_api_die 'unsafe PROXMOX_VE_API_TOKEN'

  PROXMOX_API_CURL=(
    curl
    --silent
    --show-error
    --fail-with-body
    --connect-timeout "${PROXMOX_VE_CONNECT_TIMEOUT:-10}"
  )

  case "${PROXMOX_VE_INSECURE:-false}" in
    1 | true | TRUE | yes | YES) PROXMOX_API_CURL+=(--insecure) ;;
    0 | false | FALSE | no | NO | '') ;;
    *) proxmox_api_die 'PROXMOX_VE_INSECURE must be true or false' ;;
  esac
}

proxmox_api_validate_path() {
  if [ "$#" -ne 1 ]; then
    proxmox_api_die 'usage: proxmox_api_validate_path <API path>'
  fi
  case "$1" in
    /*) ;;
    *) proxmox_api_die 'Proxmox API path must start with /' ;;
  esac
  case "$1" in
    *'?'* | *'#'* | *$'\n'* | *$'\r'*) proxmox_api_die 'unsafe Proxmox API path' ;;
  esac
}

proxmox_api_request() {
  if [ "$#" -lt 2 ]; then
    proxmox_api_die 'usage: proxmox_api_request <GET|POST> <path> [key value ...]'
  fi

  local method="$1"
  local path="$2"
  shift 2
  proxmox_api_validate_path "$path"
  if [ $(($# % 2)) -ne 0 ]; then
    proxmox_api_die 'API form parameters must be key/value pairs'
  fi
  case "$method" in
    DELETE | GET | POST) ;;
    *) proxmox_api_die 'API method must be DELETE, GET, or POST' ;;
  esac

  local request_timeout="${PROXMOX_API_REQUEST_TIMEOUT_SECONDS:-${PROXMOX_VE_REQUEST_TIMEOUT:-60}}"
  [[ "$request_timeout" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'API request timeout must be a positive integer'
  local -a args=("${PROXMOX_API_CURL[@]}" --max-time "$request_timeout" --request "$method")
  if [ "$method" = GET ] && [ "$#" -gt 0 ]; then
    args+=(--get)
  fi
  while [ "$#" -gt 0 ]; do
    local key="$1"
    local value="$2"
    shift 2
    [[ "$key" =~ ^[A-Za-z0-9_.-]+$ ]] || proxmox_api_die 'unsafe API parameter name'
    args+=(--data-urlencode "${key}=${value}")
  done

  local escaped_token="$PROXMOX_VE_API_TOKEN"
  escaped_token="${escaped_token//\\/\\\\}"
  escaped_token="${escaped_token//\"/\\\"}"
  printf 'header = "Authorization: PVEAPIToken=%s"\n' "$escaped_token" |
    "${args[@]}" --config - -- "${PROXMOX_API_BASE}${path}"
}

proxmox_api_get() {
  proxmox_api_request GET "$@"
}

proxmox_api_get_with_status() {
  if [ "$#" -ne 1 ]; then
    proxmox_api_die 'usage: proxmox_api_get_with_status <path>'
  fi
  local path="$1"
  proxmox_api_validate_path "$path"

  local request_timeout="${PROXMOX_API_REQUEST_TIMEOUT_SECONDS:-${PROXMOX_VE_REQUEST_TIMEOUT:-60}}"
  [[ "$request_timeout" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'API request timeout must be a positive integer'
  local escaped_token="$PROXMOX_VE_API_TOKEN"
  escaped_token="${escaped_token//\\/\\\\}"
  escaped_token="${escaped_token//\"/\\\"}"

  local body_file curl_status http_status
  umask 077
  body_file="$(mktemp "${TMPDIR:-/tmp}/proxmox-api-body.XXXXXX")"
  chmod 600 "$body_file"
  set +e
  http_status="$(printf 'header = "Authorization: PVEAPIToken=%s"\n' "$escaped_token" |
    "${PROXMOX_API_CURL[@]}" --max-time "$request_timeout" --request GET \
      --output "$body_file" --write-out '%{http_code}' -- "${PROXMOX_API_BASE}${path}")"
  curl_status=$?
  set -e
  if [ "$curl_status" -ne 0 ]; then
    rm -f -- "$body_file"
    proxmox_api_die "Proxmox API transport failed with curl status ${curl_status}"
  fi
  [[ "$http_status" =~ ^[0-9]{3}$ ]] || {
    rm -f -- "$body_file"
    proxmox_api_die 'Proxmox API returned an invalid HTTP status'
  }
  printf '%s\n' "$http_status"
  cat "$body_file"
  rm -f -- "$body_file"
}

proxmox_api_post() {
  proxmox_api_request POST "$@"
}

proxmox_api_delete() {
  proxmox_api_request DELETE "$@"
}

proxmox_api_urlencode() {
  if [ "$#" -ne 1 ]; then
    proxmox_api_die 'usage: proxmox_api_urlencode <value>'
  fi
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

proxmox_api_json_data_string() {
  python3 -c '
import json, sys
payload = json.load(sys.stdin)
value = payload.get("data")
if not isinstance(value, str) or not value:
    raise SystemExit("Proxmox API response did not contain a non-empty string data field")
print(value)
'
}

proxmox_api_json_task_status() {
  python3 -c '
import json, sys
data = json.load(sys.stdin).get("data")
if not isinstance(data, dict):
    raise SystemExit("Proxmox task response did not contain an object data field")
status = data.get("status")
exitstatus = data.get("exitstatus", "")
if not isinstance(status, str) or not isinstance(exitstatus, str):
    raise SystemExit("Proxmox task response contained invalid status fields")
print(status + "\t" + exitstatus)
'
}

proxmox_api_json_vm_status() {
  python3 -c '
import json, sys
data = json.load(sys.stdin).get("data")
if not isinstance(data, dict) or data.get("status") not in ("running", "stopped"):
    raise SystemExit("Proxmox VM status response was invalid")
print(data["status"])
'
}
