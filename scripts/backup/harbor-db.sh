#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init

stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
name="harbor-registry-${stamp}.dump"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
local_file="$tmp_dir/$name"

kubectl -n harbor exec harbor-database-0 -- sh -ec \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d registry -Fc' >"$local_file"
backup_store_on_nfs harbor-db "$local_file"
