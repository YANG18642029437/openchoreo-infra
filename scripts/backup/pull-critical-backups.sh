#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init
backup_require_command shasum

destination="${BACKUP_PULL_DESTINATION:-$repo_root/.private/backups/$(date -u '+%F')}"
mkdir -p "$destination"
chmod 700 "$destination"
sha256_manifest="$destination/SHA256SUMS"
: >"$sha256_manifest"

for kind in etcd openbao harbor-db; do
  latest="$(backup_ssh "$backup_nfs_host" "sudo find $backup_nfs_root/$kind -maxdepth 1 -type f -printf '%T@ %f\\n' | sort -nr | head -1 | cut -d' ' -f2-")"
  [[ "$latest" =~ ^[A-Za-z0-9._-]+$ ]] || backup_die "no safe backup found for $kind"
  backup_ssh "$backup_nfs_host" "sudo cat $backup_nfs_root/$kind/$latest" >"$destination/$latest"
  test -s "$destination/$latest" || backup_die "downloaded empty backup: $latest"
  (cd "$destination" && shasum -a 256 "$latest") >>"$sha256_manifest"
done
chmod 600 "$destination"/*
(cd "$destination" && shasum -a 256 -c SHA256SUMS)
printf 'CRITICAL_BACKUPS_PULLED directory=%s\n' "$destination"
