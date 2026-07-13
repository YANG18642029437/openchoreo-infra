#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kubeconfig="${KUBECONFIG:-$repo_root/.private/kubeconfigs/homelab-admin.yaml}"
private_dir="$repo_root/.private/openbao"
init_file="$private_dir/init.json"
harbor_file="$private_dir/harbor.env"
thunder_file="$private_dir/thunder.env"
observability_file="$private_dir/observability.env"

install -d -m 0700 "$private_dir"

kubectl --kubeconfig "$kubeconfig" -n openbao wait \
  --for=jsonpath='{.status.phase}'=Running pod/openbao-0 --timeout=10m

if kubectl --kubeconfig "$kubeconfig" -n openbao exec openbao-0 -- \
  bao operator init -status >/dev/null 2>&1; then
  test -s "$init_file" || {
    printf 'OpenBao is initialized but the protected init file is missing.\n' >&2
    exit 1
  }
else
  test ! -e "$init_file" || {
    printf 'Protected init file exists but OpenBao reports uninitialized.\n' >&2
    exit 1
  }
  umask 077
  init_json="$(kubectl --kubeconfig "$kubeconfig" -n openbao exec openbao-0 -- \
    bao operator init -key-shares=5 -key-threshold=3 -format=json)"
  install -m 0600 /dev/null "$init_file"
  printf '%s\n' "$init_json" >"$init_file"
  unset init_json
fi

chmod 0600 "$init_file"
unseal_key_1="$(jq -r '.unseal_keys_b64[0]' "$init_file")"
unseal_key_2="$(jq -r '.unseal_keys_b64[1]' "$init_file")"
unseal_key_3="$(jq -r '.unseal_keys_b64[2]' "$init_file")"
root_token="$(jq -r '.root_token' "$init_file")"
test -n "$unseal_key_1$unseal_key_2$unseal_key_3"
test -n "$root_token"

unseal_pod() {
  local pod="$1" key
  for key in "$unseal_key_1" "$unseal_key_2" "$unseal_key_3"; do
    kubectl --kubeconfig "$kubeconfig" -n openbao exec "$pod" -- \
      bao operator unseal "$key" >/dev/null
  done
}

unseal_pod openbao-0

for ordinal in 1 2; do
  pod="openbao-${ordinal}"
  for attempt in $(seq 1 60); do
    kubectl --kubeconfig "$kubeconfig" -n openbao get "pod/${pod}" >/dev/null 2>&1 && break
    sleep 5
  done
  kubectl --kubeconfig "$kubeconfig" -n openbao get "pod/${pod}" >/dev/null
  kubectl --kubeconfig "$kubeconfig" -n openbao wait \
    --for=jsonpath='{.status.phase}'=Running "pod/${pod}" --timeout=10m
  if ! kubectl --kubeconfig "$kubeconfig" -n openbao exec "$pod" -- \
    bao operator raft join http://openbao-0.openbao-internal:8200 >/dev/null 2>&1; then
    kubectl --kubeconfig "$kubeconfig" -n openbao exec "$pod" -- \
      bao status -format=json 2>/dev/null | jq -e '.initialized == true' >/dev/null
  fi
  unseal_pod "$pod"
done

bao() {
  kubectl --kubeconfig "$kubeconfig" -n openbao exec openbao-0 -- \
    env BAO_TOKEN="$root_token" bao "$@"
}

if ! bao secrets list -format=json | jq -e 'has("openchoreo/")' >/dev/null; then
  bao secrets enable -path=openchoreo -version=2 kv >/dev/null
fi
if ! bao auth list -format=json | jq -e 'has("kubernetes/")' >/dev/null; then
  bao auth enable kubernetes >/dev/null
fi

kubectl --kubeconfig "$kubeconfig" create namespace external-secrets \
  --dry-run=client -o yaml | kubectl --kubeconfig "$kubeconfig" apply -f - >/dev/null
kubectl --kubeconfig "$kubeconfig" -n external-secrets create serviceaccount external-secrets-openbao \
  --dry-run=client -o yaml | kubectl --kubeconfig "$kubeconfig" apply -f - >/dev/null
kubectl --kubeconfig "$kubeconfig" create clusterrolebinding external-secrets-openbao-tokenreview \
  --clusterrole=system:auth-delegator \
  --serviceaccount=external-secrets:external-secrets-openbao \
  --dry-run=client -o yaml | kubectl --kubeconfig "$kubeconfig" apply -f - >/dev/null

policy='path "openchoreo/data/*" { capabilities = ["read"] }'
printf '%s\n' "$policy" | kubectl --kubeconfig "$kubeconfig" -n openbao exec -i openbao-0 -- \
  env BAO_TOKEN="$root_token" bao policy write external-secrets - >/dev/null
bao write auth/kubernetes/config \
  kubernetes_host=https://kubernetes.default.svc:443 >/dev/null
bao write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-openbao \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets ttl=1h >/dev/null

if [ ! -s "$harbor_file" ]; then
  umask 077
  install -m 0600 /dev/null "$harbor_file"
  {
    printf 'HARBOR_ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 30 | tr -d '\n')"
    printf 'HARBOR_DATABASE_PASSWORD=%s\n' "$(openssl rand -base64 30 | tr -d '\n')"
    printf 'HARBOR_CORE_SECRET=%s\n' "$(openssl rand -hex 8)"
    printf 'HARBOR_CSRF_KEY=%s\n' "$(openssl rand -hex 16)"
    printf 'HARBOR_JOBSERVICE_SECRET=%s\n' "$(openssl rand -hex 8)"
    printf 'HARBOR_REGISTRY_HTTP_SECRET=%s\n' "$(openssl rand -hex 8)"
  } >"$harbor_file"
fi
chmod 0600 "$harbor_file"
set -a
source "$harbor_file"
set +a
bao kv put openchoreo/harbor \
  admin_password="$HARBOR_ADMIN_PASSWORD" \
  database_password="$HARBOR_DATABASE_PASSWORD" \
  core_secret="$HARBOR_CORE_SECRET" \
  csrf_key="$HARBOR_CSRF_KEY" \
  jobservice_secret="$HARBOR_JOBSERVICE_SECRET" \
  registry_http_secret="$HARBOR_REGISTRY_HTTP_SECRET" >/dev/null

if [ ! -s "$thunder_file" ]; then
  umask 077
  install -m 0600 /dev/null "$thunder_file"
  {
    printf 'THUNDER_ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 30 | tr -d '\n')"
    printf 'THUNDER_DEVELOPER_PASSWORD=%s\n' "$(openssl rand -base64 30 | tr -d '\n')"
    printf 'THUNDER_PLATFORM_ENGINEER_PASSWORD=%s\n' "$(openssl rand -base64 30 | tr -d '\n')"
    printf 'THUNDER_SRE_PASSWORD=%s\n' "$(openssl rand -base64 30 | tr -d '\n')"
    printf 'BACKSTAGE_BACKEND_SECRET=%s\n' "$(openssl rand -base64 48 | tr -d '\n')"
    printf 'BACKSTAGE_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'DEFAULT_APP_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'RCA_AGENT_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'SYSTEM_APP_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'SERVICE_MCP_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'WORKLOAD_PUBLISHER_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'OBSERVER_READER_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
    printf 'FINOPS_AGENT_CLIENT_SECRET=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
  } >"$thunder_file"
fi
chmod 0600 "$thunder_file"
set -a
source "$thunder_file"
set +a
bao kv put openchoreo/thunder \
  admin_password="$THUNDER_ADMIN_PASSWORD" \
  developer_password="$THUNDER_DEVELOPER_PASSWORD" \
  platform_engineer_password="$THUNDER_PLATFORM_ENGINEER_PASSWORD" \
  sre_password="$THUNDER_SRE_PASSWORD" \
  backstage_backend_secret="$BACKSTAGE_BACKEND_SECRET" \
  backstage_client_secret="$BACKSTAGE_CLIENT_SECRET" \
  default_app_client_secret="$DEFAULT_APP_CLIENT_SECRET" \
  rca_agent_client_secret="$RCA_AGENT_CLIENT_SECRET" \
  system_app_client_secret="$SYSTEM_APP_CLIENT_SECRET" \
  service_mcp_client_secret="$SERVICE_MCP_CLIENT_SECRET" \
  workload_publisher_client_secret="$WORKLOAD_PUBLISHER_CLIENT_SECRET" \
  observer_reader_client_secret="$OBSERVER_READER_CLIENT_SECRET" \
  finops_agent_client_secret="$FINOPS_AGENT_CLIENT_SECRET" >/dev/null

if [ ! -s "$observability_file" ]; then
  umask 077
  install -m 0600 /dev/null "$observability_file"
  {
    printf 'OPENSEARCH_USERNAME=admin\n'
    printf 'OPENSEARCH_PASSWORD=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
  } >"$observability_file"
fi
chmod 0600 "$observability_file"
set -a
source "$observability_file"
set +a
bao kv put openchoreo/observability \
  opensearch_username="$OPENSEARCH_USERNAME" \
  opensearch_password="$OPENSEARCH_PASSWORD" >/dev/null

unset root_token unseal_key_1 unseal_key_2 unseal_key_3 \
  HARBOR_ADMIN_PASSWORD HARBOR_DATABASE_PASSWORD \
  HARBOR_CORE_SECRET HARBOR_CSRF_KEY HARBOR_JOBSERVICE_SECRET \
  HARBOR_REGISTRY_HTTP_SECRET THUNDER_ADMIN_PASSWORD \
  THUNDER_DEVELOPER_PASSWORD THUNDER_PLATFORM_ENGINEER_PASSWORD \
  THUNDER_SRE_PASSWORD BACKSTAGE_BACKEND_SECRET BACKSTAGE_CLIENT_SECRET \
  DEFAULT_APP_CLIENT_SECRET RCA_AGENT_CLIENT_SECRET SYSTEM_APP_CLIENT_SECRET \
  SERVICE_MCP_CLIENT_SECRET WORKLOAD_PUBLISHER_CLIENT_SECRET \
  OBSERVER_READER_CLIENT_SECRET FINOPS_AGENT_CLIENT_SECRET \
  OPENSEARCH_USERNAME OPENSEARCH_PASSWORD
printf 'OpenBao initialization: PASS\n'
