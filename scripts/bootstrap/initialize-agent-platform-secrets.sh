#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kubeconfig="${KUBECONFIG:-$repo_root/.private/kubeconfigs/homelab-admin.yaml}"
secret_file="${AGENT_PLATFORM_SECRETS_FILE:-$repo_root/.private/openbao/agent-platform.env}"
init_file="$repo_root/.private/openbao/init.json"
minio_secret_path='openchoreo/agent-platform/development/minio'
redis_secret_path='openchoreo/agent-platform/development/redis'
langfuse_secret_path='openchoreo/agent-platform/development/langfuse'

for command_name in kubectl jq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'missing command: %s\n' "$command_name" >&2
    exit 1
  }
done

test -s "$kubeconfig" || {
  printf 'missing kubeconfig: %s\n' "$kubeconfig" >&2
  exit 1
}
test -s "$secret_file" || {
  printf 'missing Agent Platform secret file: %s\n' "$secret_file" >&2
  exit 1
}
test -s "$init_file" || {
  printf 'missing protected OpenBao init file: %s\n' "$init_file" >&2
  exit 1
}

set -a
source "$secret_file"
set +a
test "${MINIO_ROOT_USER:-}" = agent-platform
test -n "${MINIO_ROOT_PASSWORD:-}"
test "${#MINIO_ROOT_PASSWORD}" -ge 32
test -n "${REDIS_PASSWORD:-}"
test "${#REDIS_PASSWORD}" -ge 32
test "${#LANGFUSE_SALT}" -ge 32
test "${#LANGFUSE_ENCRYPTION_KEY}" -eq 64
test "${#LANGFUSE_NEXTAUTH_SECRET}" -ge 32
test -n "${LANGFUSE_ADMIN_EMAIL:-}"
test "${#LANGFUSE_ADMIN_PASSWORD}" -ge 32
test "${LANGFUSE_PROJECT_PUBLIC_KEY#pk-lf-}" != "$LANGFUSE_PROJECT_PUBLIC_KEY"
test "${LANGFUSE_PROJECT_SECRET_KEY#sk-lf-}" != "$LANGFUSE_PROJECT_SECRET_KEY"
test "${#LANGFUSE_POSTGRES_PASSWORD}" -ge 32
test "${#LANGFUSE_REDIS_PASSWORD}" -ge 32
test "$LANGFUSE_MINIO_ACCESS_KEY" = langfuse
test "${#LANGFUSE_MINIO_SECRET_KEY}" -ge 32
test "$LANGFUSE_CLICKHOUSE_USERNAME" = langfuse
test "${#LANGFUSE_CLICKHOUSE_PASSWORD}" -ge 32
root_token="$(jq -er '.root_token' "$init_file")"

kubectl --kubeconfig "$kubeconfig" -n openbao wait \
  --for=jsonpath='{.status.phase}'=Running pod/openbao-0 --timeout=10m >/dev/null

bao() {
  kubectl --kubeconfig "$kubeconfig" -n openbao exec openbao-0 -- \
    env BAO_TOKEN="$root_token" bao "$@"
}

current_json="$(bao kv get -format=json "$minio_secret_path" 2>/dev/null || true)"
current_user="$(printf '%s' "$current_json" | jq -r '.data.data.root_user // empty')"
current_password="$(printf '%s' "$current_json" | jq -r '.data.data.root_password // empty')"

if [ "$current_user" != "$MINIO_ROOT_USER" ] || \
  [ "$current_password" != "$MINIO_ROOT_PASSWORD" ]; then
  bao kv put "$minio_secret_path" \
    root_user="$MINIO_ROOT_USER" \
    root_password="$MINIO_ROOT_PASSWORD" >/dev/null
fi

verified_json="$(bao kv get -format=json "$minio_secret_path")"
printf '%s' "$verified_json" | jq -e \
  '.data.data.root_user | type == "string" and length > 0' >/dev/null
printf '%s' "$verified_json" | jq -e \
  '.data.data.root_password | type == "string" and length >= 32' >/dev/null

current_redis_json="$(bao kv get -format=json "$redis_secret_path" 2>/dev/null || true)"
current_redis_password="$(printf '%s' "$current_redis_json" | jq -r '.data.data.password // empty')"
current_langfuse_redis_password="$(printf '%s' "$current_redis_json" | jq -r '.data.data.langfuse_password // empty')"
if [ "$current_redis_password" != "$REDIS_PASSWORD" ] || \
  [ "$current_langfuse_redis_password" != "$LANGFUSE_REDIS_PASSWORD" ]; then
  bao kv put "$redis_secret_path" \
    password="$REDIS_PASSWORD" \
    langfuse_password="$LANGFUSE_REDIS_PASSWORD" >/dev/null
fi

verified_redis_json="$(bao kv get -format=json "$redis_secret_path")"
printf '%s' "$verified_redis_json" | jq -e \
  '.data.data.password | type == "string" and length >= 32' >/dev/null
printf '%s' "$verified_redis_json" | jq -e \
  '.data.data.langfuse_password | type == "string" and length >= 32' >/dev/null

# Langfuse 路径一次写入全部应用字段，回读只验证类型、长度和固定标识，不输出值。
current_langfuse_json="$(bao kv get -format=json "$langfuse_secret_path" 2>/dev/null || true)"
current_langfuse_data="$(printf '%s' "$current_langfuse_json" | jq -c '.data.data // {}')"
desired_langfuse_data="$(jq -cn \
  --arg salt "$LANGFUSE_SALT" \
  --arg encryption_key "$LANGFUSE_ENCRYPTION_KEY" \
  --arg nextauth_secret "$LANGFUSE_NEXTAUTH_SECRET" \
  --arg admin_email "$LANGFUSE_ADMIN_EMAIL" \
  --arg admin_password "$LANGFUSE_ADMIN_PASSWORD" \
  --arg project_public_key "$LANGFUSE_PROJECT_PUBLIC_KEY" \
  --arg project_secret_key "$LANGFUSE_PROJECT_SECRET_KEY" \
  --arg postgres_password "$LANGFUSE_POSTGRES_PASSWORD" \
  --arg redis_password "$LANGFUSE_REDIS_PASSWORD" \
  --arg minio_access_key "$LANGFUSE_MINIO_ACCESS_KEY" \
  --arg minio_secret_key "$LANGFUSE_MINIO_SECRET_KEY" \
  --arg clickhouse_username "$LANGFUSE_CLICKHOUSE_USERNAME" \
  --arg clickhouse_password "$LANGFUSE_CLICKHOUSE_PASSWORD" \
  '{salt:$salt,encryption_key:$encryption_key,nextauth_secret:$nextauth_secret,
    admin_email:$admin_email,admin_password:$admin_password,
    project_public_key:$project_public_key,project_secret_key:$project_secret_key,
    postgres_password:$postgres_password,redis_password:$redis_password,
    minio_access_key:$minio_access_key,minio_secret_key:$minio_secret_key,
    clickhouse_username:$clickhouse_username,clickhouse_password:$clickhouse_password}')"

if [ "$current_langfuse_data" != "$desired_langfuse_data" ]; then
  bao kv put "$langfuse_secret_path" \
    salt="$LANGFUSE_SALT" \
    encryption_key="$LANGFUSE_ENCRYPTION_KEY" \
    nextauth_secret="$LANGFUSE_NEXTAUTH_SECRET" \
    admin_email="$LANGFUSE_ADMIN_EMAIL" \
    admin_password="$LANGFUSE_ADMIN_PASSWORD" \
    project_public_key="$LANGFUSE_PROJECT_PUBLIC_KEY" \
    project_secret_key="$LANGFUSE_PROJECT_SECRET_KEY" \
    postgres_password="$LANGFUSE_POSTGRES_PASSWORD" \
    redis_password="$LANGFUSE_REDIS_PASSWORD" \
    minio_access_key="$LANGFUSE_MINIO_ACCESS_KEY" \
    minio_secret_key="$LANGFUSE_MINIO_SECRET_KEY" \
    clickhouse_username="$LANGFUSE_CLICKHOUSE_USERNAME" \
    clickhouse_password="$LANGFUSE_CLICKHOUSE_PASSWORD" >/dev/null
fi

verified_langfuse_json="$(bao kv get -format=json "$langfuse_secret_path")"
printf '%s' "$verified_langfuse_json" | jq -e '
  .data.data as $d |
  ($d.salt | type == "string" and length >= 32) and
  ($d.encryption_key | type == "string" and length == 64) and
  ($d.nextauth_secret | type == "string" and length >= 32) and
  ($d.admin_email | type == "string" and length > 0) and
  ($d.admin_password | type == "string" and length >= 32) and
  ($d.project_public_key | type == "string" and startswith("pk-lf-")) and
  ($d.project_secret_key | type == "string" and startswith("sk-lf-")) and
  ($d.postgres_password | type == "string" and length >= 32) and
  ($d.redis_password | type == "string" and length >= 32) and
  ($d.minio_access_key == "langfuse") and
  ($d.minio_secret_key | type == "string" and length >= 32) and
  ($d.clickhouse_username == "langfuse") and
  ($d.clickhouse_password | type == "string" and length >= 32)
' >/dev/null

unset root_token current_json current_user current_password verified_json \
  current_redis_json current_redis_password current_langfuse_redis_password \
  verified_redis_json current_langfuse_json current_langfuse_data \
  desired_langfuse_data verified_langfuse_json \
  MINIO_ROOT_USER MINIO_ROOT_PASSWORD REDIS_PASSWORD \
  LANGFUSE_SALT LANGFUSE_ENCRYPTION_KEY LANGFUSE_NEXTAUTH_SECRET \
  LANGFUSE_ADMIN_EMAIL LANGFUSE_ADMIN_PASSWORD \
  LANGFUSE_PROJECT_PUBLIC_KEY LANGFUSE_PROJECT_SECRET_KEY \
  LANGFUSE_POSTGRES_PASSWORD LANGFUSE_REDIS_PASSWORD \
  LANGFUSE_MINIO_ACCESS_KEY LANGFUSE_MINIO_SECRET_KEY \
  LANGFUSE_CLICKHOUSE_USERNAME LANGFUSE_CLICKHOUSE_PASSWORD
printf 'Agent Platform OpenBao secret initialization: PASS\n'
