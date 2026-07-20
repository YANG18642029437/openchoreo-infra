#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
prepare="$repo_root/scripts/prepare/agent-platform-secrets.sh"
bootstrap="$repo_root/scripts/bootstrap/initialize-agent-platform-secrets.sh"

test -x "$prepare"
test -x "$bootstrap"
bash -n "$prepare"
bash -n "$bootstrap"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-platform-secrets.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
secret_file="$tmp_dir/agent-platform.env"

first_output="$(AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
test -s "$secret_file"
grep -q '^MINIO_ROOT_USER=' "$secret_file"
grep -q '^MINIO_ROOT_PASSWORD=' "$secret_file"
grep -q '^REDIS_PASSWORD=' "$secret_file"
for key in \
  LANGFUSE_SALT LANGFUSE_ENCRYPTION_KEY LANGFUSE_NEXTAUTH_SECRET \
  LANGFUSE_ADMIN_EMAIL LANGFUSE_ADMIN_PASSWORD \
  LANGFUSE_PROJECT_PUBLIC_KEY LANGFUSE_PROJECT_SECRET_KEY \
  LANGFUSE_POSTGRES_PASSWORD LANGFUSE_REDIS_PASSWORD \
  LANGFUSE_MINIO_ACCESS_KEY LANGFUSE_MINIO_SECRET_KEY \
  LANGFUSE_CLICKHOUSE_USERNAME LANGFUSE_CLICKHOUSE_PASSWORD; do
  grep -q "^${key}=" "$secret_file"
done
case "$(uname -s)" in
  Darwin) file_mode="$(stat -f '%Lp' "$secret_file")" ;;
  Linux) file_mode="$(stat -c '%a' "$secret_file")" ;;
  *) exit 1 ;;
esac
test "$file_mode" = 600

set -a
source "$secret_file"
set +a
test "$MINIO_ROOT_USER" = agent-platform
test "${#MINIO_ROOT_PASSWORD}" -ge 32
test "${#REDIS_PASSWORD}" -ge 32
test "${#LANGFUSE_SALT}" -ge 32
test "${#LANGFUSE_ENCRYPTION_KEY}" -eq 64
test "${#LANGFUSE_NEXTAUTH_SECRET}" -ge 32
test "${#LANGFUSE_ADMIN_PASSWORD}" -ge 32
test "$LANGFUSE_PROJECT_PUBLIC_KEY" != "$LANGFUSE_PROJECT_SECRET_KEY"
test "${#LANGFUSE_POSTGRES_PASSWORD}" -ge 32
test "${#LANGFUSE_REDIS_PASSWORD}" -ge 32
case "$LANGFUSE_POSTGRES_PASSWORD" in *[!0-9a-fA-F]*) exit 1 ;; esac
case "$LANGFUSE_REDIS_PASSWORD" in *[!0-9a-fA-F]*) exit 1 ;; esac
test "${#LANGFUSE_MINIO_SECRET_KEY}" -ge 32
test "$LANGFUSE_CLICKHOUSE_USERNAME" = langfuse
if printf '%s\n' "$first_output" | grep -Fq "$MINIO_ROOT_PASSWORD"; then
  printf 'prepare script leaked generated password\n' >&2
  exit 1
fi
if printf '%s\n' "$first_output" | grep -Fq "$REDIS_PASSWORD"; then
  printf 'prepare script leaked generated Redis password\n' >&2
  exit 1
fi
for secret_value in \
  "$LANGFUSE_SALT" "$LANGFUSE_ENCRYPTION_KEY" "$LANGFUSE_NEXTAUTH_SECRET" \
  "$LANGFUSE_ADMIN_PASSWORD" "$LANGFUSE_PROJECT_SECRET_KEY" \
  "$LANGFUSE_POSTGRES_PASSWORD" "$LANGFUSE_REDIS_PASSWORD" \
  "$LANGFUSE_MINIO_SECRET_KEY" "$LANGFUSE_CLICKHOUSE_PASSWORD"; do
  if printf '%s\n' "$first_output" | grep -Fq "$secret_value"; then
    printf 'prepare script leaked a generated Langfuse secret\n' >&2
    exit 1
  fi
done

first_hash="$(shasum -a 256 "$secret_file" | awk '{print $1}')"
second_output="$(AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
second_hash="$(shasum -a 256 "$secret_file" | awk '{print $1}')"
test "$first_hash" = "$second_hash"
if printf '%s\n' "$second_output" | grep -Fq "$MINIO_ROOT_PASSWORD"; then
  printf 'prepare rerun leaked existing password\n' >&2
  exit 1
fi
if printf '%s\n' "$second_output" | grep -Fq "$REDIS_PASSWORD"; then
  printf 'prepare rerun leaked existing Redis password\n' >&2
  exit 1
fi

# 显式轮换只能改变 Langfuse Redis 密码，且不得把新旧值写到标准输出。
old_langfuse_redis_password="$LANGFUSE_REDIS_PASSWORD"
rotate_output="$(ROTATE_LANGFUSE_REDIS_PASSWORD=1 \
  AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
set -a
source "$secret_file"
set +a
test "$LANGFUSE_REDIS_PASSWORD" != "$old_langfuse_redis_password"
case "$LANGFUSE_REDIS_PASSWORD" in *[!0-9a-fA-F]*) exit 1 ;; esac
if printf '%s\n' "$rotate_output" | grep -Fq "$LANGFUSE_REDIS_PASSWORD"; then
  printf 'prepare rotation leaked the new Langfuse Redis password\n' >&2
  exit 1
fi
unset old_langfuse_redis_password rotate_output

fake_repo="$tmp_dir/fake-repo"
mkdir -p "$fake_repo/scripts/prepare"
cp "$prepare" "$fake_repo/scripts/prepare/agent-platform-secrets.sh"
"$fake_repo/scripts/prepare/agent-platform-secrets.sh" >/dev/null
test -s "$fake_repo/.private/openbao/agent-platform.env" || {
  printf 'prepare default path is not rooted at the repository\n' >&2
  exit 1
}
test ! -e "$fake_repo/scripts/.private/openbao/agent-platform.env"

grep -Fq 'openchoreo/agent-platform/development/minio' "$bootstrap"
grep -Fq 'openchoreo/agent-platform/development/redis' "$bootstrap"
grep -Fq 'openchoreo/agent-platform/development/langfuse' "$bootstrap"
grep -Fq 'root_user' "$bootstrap"
grep -Fq 'root_password' "$bootstrap"
grep -Fq 'REDIS_PASSWORD' "$bootstrap"
grep -Fq 'LANGFUSE_PROJECT_SECRET_KEY' "$bootstrap"
grep -Fq 'agent-platform.env' "$bootstrap"
grep -Fq 'ROTATE_LANGFUSE_REDIS_PASSWORD' "$prepare"

printf 'Agent Platform local secret contract: PASS\n'
