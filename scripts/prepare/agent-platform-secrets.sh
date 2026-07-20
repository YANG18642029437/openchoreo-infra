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

# 只在字段缺失时追加，保证重跑不会轮换已经投入使用的 Langfuse 凭据。
append_if_missing() {
  key="$1"
  value="$2"
  if ! grep -q "^${key}=" "$secret_file"; then
    printf '%s=%s\n' "$key" "$value" >>"$secret_file"
  fi
}

umask 077
append_if_missing LANGFUSE_SALT "$(openssl rand -base64 32 | tr -d '\n')"
append_if_missing LANGFUSE_ENCRYPTION_KEY "$(openssl rand -hex 32)"
append_if_missing LANGFUSE_NEXTAUTH_SECRET "$(openssl rand -base64 36 | tr -d '\n')"
append_if_missing LANGFUSE_ADMIN_EMAIL "langfuse-admin@agent-platform.local"
append_if_missing LANGFUSE_ADMIN_PASSWORD "$(openssl rand -base64 36 | tr -d '\n')"
append_if_missing LANGFUSE_PROJECT_PUBLIC_KEY "pk-lf-$(openssl rand -hex 16)"
append_if_missing LANGFUSE_PROJECT_SECRET_KEY "sk-lf-$(openssl rand -hex 32)"
append_if_missing LANGFUSE_POSTGRES_PASSWORD "$(openssl rand -hex 32)"
append_if_missing LANGFUSE_REDIS_PASSWORD "$(openssl rand -hex 32)"
append_if_missing LANGFUSE_MINIO_ACCESS_KEY "langfuse"
append_if_missing LANGFUSE_MINIO_SECRET_KEY "$(openssl rand -base64 36 | tr -d '\n')"
append_if_missing LANGFUSE_CLICKHOUSE_USERNAME "langfuse"
append_if_missing LANGFUSE_CLICKHOUSE_PASSWORD "$(openssl rand -base64 36 | tr -d '\n')"
unset key value

set -a
source "$secret_file"
set +a

# URI 中使用的密码限定为十六进制；首次接入时安全轮换历史 base64 值，之后保持幂等。
replace_with_hex_if_needed() {
  variable_name="$1"
  eval "variable_value=\${$variable_name}"
  case "$variable_value" in
    ''|*[!0-9a-fA-F]*)
      replacement="$(openssl rand -hex 32)"
      temporary_file="$(mktemp "${secret_file}.XXXXXX")"
      while IFS= read -r line; do
        case "$line" in
          "$variable_name="*) printf '%s=%s\n' "$variable_name" "$replacement" ;;
          *) printf '%s\n' "$line" ;;
        esac
      done <"$secret_file" >"$temporary_file"
      chmod 0600 "$temporary_file"
      mv "$temporary_file" "$secret_file"
      ;;
  esac
  unset variable_name variable_value replacement temporary_file line
}

replace_with_hex_if_needed LANGFUSE_POSTGRES_PASSWORD
replace_with_hex_if_needed LANGFUSE_REDIS_PASSWORD

# 仅在显式要求时轮换 Langfuse Redis 凭据，用于日志误暴露等应急场景。
if [ "${ROTATE_LANGFUSE_REDIS_PASSWORD:-0}" = 1 ]; then
  replacement="$(openssl rand -hex 32)"
  temporary_file="$(mktemp "${secret_file}.XXXXXX")"
  while IFS= read -r line; do
    case "$line" in
      LANGFUSE_REDIS_PASSWORD=*) printf 'LANGFUSE_REDIS_PASSWORD=%s\n' "$replacement" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$secret_file" >"$temporary_file"
  chmod 0600 "$temporary_file"
  mv "$temporary_file" "$secret_file"
  unset replacement temporary_file line
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

test "${#LANGFUSE_SALT}" -ge 32 || {
  printf 'LANGFUSE_SALT must contain at least 32 characters\n' >&2
  exit 1
}
test "${#LANGFUSE_ENCRYPTION_KEY}" -eq 64 || {
  printf 'LANGFUSE_ENCRYPTION_KEY must contain exactly 64 hexadecimal characters\n' >&2
  exit 1
}
test "${#LANGFUSE_NEXTAUTH_SECRET}" -ge 32
test -n "${LANGFUSE_ADMIN_EMAIL:-}"
test "${#LANGFUSE_ADMIN_PASSWORD}" -ge 32
case "$LANGFUSE_PROJECT_PUBLIC_KEY" in pk-lf-*) ;; *) exit 1 ;; esac
case "$LANGFUSE_PROJECT_SECRET_KEY" in sk-lf-*) ;; *) exit 1 ;; esac
test "$LANGFUSE_PROJECT_PUBLIC_KEY" != "$LANGFUSE_PROJECT_SECRET_KEY"
test "${#LANGFUSE_POSTGRES_PASSWORD}" -ge 32
test "${#LANGFUSE_REDIS_PASSWORD}" -ge 32
case "$LANGFUSE_POSTGRES_PASSWORD" in *[!0-9a-fA-F]*) exit 1 ;; esac
case "$LANGFUSE_REDIS_PASSWORD" in *[!0-9a-fA-F]*) exit 1 ;; esac
test "$LANGFUSE_MINIO_ACCESS_KEY" = langfuse
test "${#LANGFUSE_MINIO_SECRET_KEY}" -ge 32
test "$LANGFUSE_CLICKHOUSE_USERNAME" = langfuse
test "${#LANGFUSE_CLICKHOUSE_PASSWORD}" -ge 32

unset MINIO_ROOT_USER MINIO_ROOT_PASSWORD REDIS_PASSWORD \
  LANGFUSE_SALT LANGFUSE_ENCRYPTION_KEY LANGFUSE_NEXTAUTH_SECRET \
  LANGFUSE_ADMIN_EMAIL LANGFUSE_ADMIN_PASSWORD \
  LANGFUSE_PROJECT_PUBLIC_KEY LANGFUSE_PROJECT_SECRET_KEY \
  LANGFUSE_POSTGRES_PASSWORD LANGFUSE_REDIS_PASSWORD \
  LANGFUSE_MINIO_ACCESS_KEY LANGFUSE_MINIO_SECRET_KEY \
  LANGFUSE_CLICKHOUSE_USERNAME LANGFUSE_CLICKHOUSE_PASSWORD
printf 'Agent Platform local secret preparation: PASS\n'
