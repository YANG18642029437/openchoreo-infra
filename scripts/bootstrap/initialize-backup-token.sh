#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init
backup_require_command jq

init_file="${OPENBAO_INIT_FILE:-$repo_root/.private/openbao/init.json}"
output_file="${OPENBAO_BACKUP_ENV:-$repo_root/.private/openbao/backup.env}"
backup_require_file "$init_file"
root_token="$(jq -er '.root_token' "$init_file")"
policy='path "sys/storage/raft/snapshot" { capabilities = ["read"] }'

printf '%s\n' "$policy" | kubectl -n openbao exec -i openbao-0 -- \
  env BAO_ADDR=http://openbao-active:8200 BAO_TOKEN="$root_token" \
  bao policy write phase05-snapshot - >/dev/null
token_json="$(kubectl -n openbao exec openbao-0 -- \
  env BAO_ADDR=http://openbao-active:8200 BAO_TOKEN="$root_token" \
  bao token create -policy=phase05-snapshot -orphan -period=24h -format=json)"
backup_token="$(jq -er '.auth.client_token' <<<"$token_json")"
mkdir -p "$(dirname "$output_file")"
printf 'OPENBAO_BACKUP_TOKEN=%q\n' "$backup_token" >"$output_file"
chmod 600 "$output_file"
unset root_token backup_token token_json
printf 'OPENBAO_BACKUP_TOKEN_INITIALIZED file=%s\n' "$output_file"
