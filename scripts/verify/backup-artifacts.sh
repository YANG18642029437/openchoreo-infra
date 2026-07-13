#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init
backup_require_command shasum

directory="${BACKUP_VERIFY_DIRECTORY:-$repo_root/.private/backups/$(date -u '+%F')}"
manifest="$directory/SHA256SUMS"
backup_require_file "$manifest"
(cd "$directory" && shasum -a 256 -c SHA256SUMS)

now="$(date -u '+%s')"
for pattern in 'phase05-*.snapshot' 'openbao-raft-*.snap' 'harbor-registry-*.dump'; do
  file="$(find "$directory" -maxdepth 1 -type f -name "$pattern" -print | sort | tail -1)"
  backup_require_file "$file"
  test -s "$file" || backup_die "empty artifact: $file"
  modified="$(stat -f '%m' "$file")"
  age=$((now - modified))
  ((age >= 0 && age <= 86400)) || backup_die "artifact is older than 24 hours: $file"
done

etcd_file="$(find "$directory" -maxdepth 1 -type f -name 'phase05-*.snapshot' -print | sort | tail -1)"
harbor_file="$(find "$directory" -maxdepth 1 -type f -name 'harbor-registry-*.dump' -print | sort | tail -1)"
openbao_file="$(find "$directory" -maxdepth 1 -type f -name 'openbao-raft-*.snap' -print | sort | tail -1)"

# Read-only checks use the matching platform binaries; no restore occurs.
kubectl -n harbor exec -i harbor-database-0 -- pg_restore --list <"$harbor_file" >/dev/null
gzip -t "$openbao_file"
openbao_entries="$(tar -tzf "$openbao_file")"
for entry in meta.json state.bin SHA256SUMS SHA256SUMS.sealed; do
  grep -qx "$entry" <<<"$openbao_entries" || backup_die "OpenBao snapshot lacks $entry"
done
test "$(od -An -tx1 -j16 -N4 "$etcd_file" | tr -d ' \n')" = 'edda0ced' || \
  backup_die 'etcd snapshot lacks the bbolt metadata magic'

printf 'Phase 05 backup artifacts: PASS directory=%s\n' "$directory"
