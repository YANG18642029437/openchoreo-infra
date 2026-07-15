#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kubeconfig="${KUBECONFIG:-$repo_root/.private/kubeconfigs/homelab-admin.yaml}"
secret_file="${AGENT_PLATFORM_SECRETS_FILE:-$repo_root/.private/openbao/agent-platform.env}"
init_file="$repo_root/.private/openbao/init.json"
secret_path='openchoreo/agent-platform/development/minio'

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
root_token="$(jq -er '.root_token' "$init_file")"

kubectl --kubeconfig "$kubeconfig" -n openbao wait \
  --for=jsonpath='{.status.phase}'=Running pod/openbao-0 --timeout=10m >/dev/null

bao() {
  kubectl --kubeconfig "$kubeconfig" -n openbao exec openbao-0 -- \
    env BAO_TOKEN="$root_token" bao "$@"
}

current_json="$(bao kv get -format=json "$secret_path" 2>/dev/null || true)"
current_user="$(printf '%s' "$current_json" | jq -r '.data.data.root_user // empty')"
current_password="$(printf '%s' "$current_json" | jq -r '.data.data.root_password // empty')"

if [ "$current_user" != "$MINIO_ROOT_USER" ] || \
  [ "$current_password" != "$MINIO_ROOT_PASSWORD" ]; then
  bao kv put "$secret_path" \
    root_user="$MINIO_ROOT_USER" \
    root_password="$MINIO_ROOT_PASSWORD" >/dev/null
fi

verified_json="$(bao kv get -format=json "$secret_path")"
printf '%s' "$verified_json" | jq -e \
  '.data.data.root_user | type == "string" and length > 0' >/dev/null
printf '%s' "$verified_json" | jq -e \
  '.data.data.root_password | type == "string" and length >= 32' >/dev/null

unset root_token current_json current_user current_password verified_json \
  MINIO_ROOT_USER MINIO_ROOT_PASSWORD
printf 'Agent Platform OpenBao secret initialization: PASS\n'
