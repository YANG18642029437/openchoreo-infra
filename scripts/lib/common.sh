#!/usr/bin/env bash
# Sourcing this library intentionally enables errexit, nounset, and pipefail in the caller.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    die 'usage: require_command <command>'
  fi
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    die 'usage: require_file <path>'
  fi
  test -f "$1" || die "missing file: $1"
}

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

redact() {
  local key_re='([[:alnum:]_]*([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]))'
  sed -E \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\\1\\2\"[redacted]\"/g" \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*=[[:space:]]*)'[^']*'/\\1\\2'[redacted]'/g" \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*=[[:space:]]*)[^[:space:]&,;\"']+/\\1\\2[redacted]/g" \
    -e "s/(^|[^[:alnum:]_])(\"?(${key_re})\"?[[:space:]]*:[[:space:]]*).*/\\1\\2[redacted]/g"
}
