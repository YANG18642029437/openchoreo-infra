#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  test -f "$1" || die "missing file: $1"
}

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

redact() {
  sed -E \
    -e 's/(token|password|secret)([=:])[[:graph:]]+/\1\2[redacted]/Ig' \
    -e 's/(PROXMOX_VE_API_TOKEN=).*/\1[redacted]/'
}
