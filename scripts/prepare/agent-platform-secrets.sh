#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
secret_file="${AGENT_PLATFORM_SECRETS_FILE:-$repo_root/.private/openbao/agent-platform.env}"
secret_dir="$(dirname "$secret_file")"

command -v openssl >/dev/null 2>&1 || {
  printf 'missing command: openssl\n' >&2
  exit 1
}

install -d -m 0700 "$secret_dir"
chmod 0700 "$secret_dir"

if [ ! -s "$secret_file" ]; then
  umask 077
  password="$(openssl rand -base64 36 | tr -d '\n')"
  install -m 0600 /dev/null "$secret_file"
  {
    printf 'MINIO_ROOT_USER=agent-platform\n'
    printf 'MINIO_ROOT_PASSWORD=%s\n' "$password"
  } >"$secret_file"
  unset password
fi

chmod 0600 "$secret_file"

if ! grep -q '^REDIS_PASSWORD=' "$secret_file"; then
  umask 077
  redis_password="$(openssl rand -base64 36 | tr -d '\n')"
  printf 'REDIS_PASSWORD=%s\n' "$redis_password" >>"$secret_file"
  unset redis_password
fi

set -a
source "$secret_file"
set +a

test "${MINIO_ROOT_USER:-}" = agent-platform || {
  printf 'MINIO_ROOT_USER must be agent-platform\n' >&2
  exit 1
}
test -n "${MINIO_ROOT_PASSWORD:-}" || {
  printf 'MINIO_ROOT_PASSWORD is required\n' >&2
  exit 1
}
test "${#MINIO_ROOT_PASSWORD}" -ge 32 || {
  printf 'MINIO_ROOT_PASSWORD must contain at least 32 characters\n' >&2
  exit 1
}
test -n "${REDIS_PASSWORD:-}" || {
  printf 'REDIS_PASSWORD is required\n' >&2
  exit 1
}
test "${#REDIS_PASSWORD}" -ge 32 || {
  printf 'REDIS_PASSWORD must contain at least 32 characters\n' >&2
  exit 1
}

unset MINIO_ROOT_USER MINIO_ROOT_PASSWORD REDIS_PASSWORD
printf 'Agent Platform local secret preparation: PASS\n'
