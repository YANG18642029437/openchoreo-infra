#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init

token_file="${OPENBAO_BACKUP_ENV:-$repo_root/.private/openbao/backup.env}"
backup_require_file "$token_file"
source "$token_file"
: "${OPENBAO_BACKUP_TOKEN:?missing OPENBAO_BACKUP_TOKEN}"
stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
name="openbao-raft-${stamp}.snap"
remote_path="/tmp/$name"
tmp_dir="$(mktemp -d)"
trap 'kubectl -n openbao exec openbao-0 -- rm -f "$remote_path" >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT
local_file="$tmp_dir/$name"

kubectl -n openbao exec openbao-0 -- env BAO_ADDR=http://openbao-active:8200 \
  BAO_TOKEN="$OPENBAO_BACKUP_TOKEN" bao operator raft snapshot save "$remote_path" >/dev/null
kubectl -n openbao cp "openbao-0:$remote_path" "$local_file" >/dev/null
backup_store_on_nfs openbao "$local_file"
