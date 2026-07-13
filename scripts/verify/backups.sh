#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

required=(
  scripts/lib/backup-common.sh
  scripts/bootstrap/initialize-backup-token.sh
  scripts/backup/etcd-snapshot.sh
  scripts/backup/openbao-snapshot.sh
  scripts/backup/harbor-db.sh
  scripts/backup/pull-critical-backups.sh
  scripts/verify/backup-artifacts.sh
  ansible/playbooks/18-k3s-snapshot-policy.yml
  ansible/roles/k3s_snapshot/tasks/main.yml
  ansible/roles/k3s_snapshot/handlers/main.yml
  runbooks/40-backup-and-restore.md
)
for path in "${required[@]}"; do
  test -f "$path" || { printf 'missing Phase 05 backup file: %s\n' "$path" >&2; exit 1; }
done

grep -q 'etcd-snapshot-schedule-cron: "0 \*/6 \* \* \*"' ansible/roles/k3s/templates/config.yaml.j2
grep -q 'etcd-snapshot-retention: 56' ansible/roles/k3s/templates/config.yaml.j2
grep -q 'serial: 1' ansible/playbooks/18-k3s-snapshot-policy.yml
grep -q 'k3s etcd-snapshot save' scripts/backup/etcd-snapshot.sh
grep -q 'operator raft snapshot save' scripts/backup/openbao-snapshot.sh
grep -q 'pg_dump' scripts/backup/harbor-db.sh
grep -q '.private/backups' scripts/backup/pull-critical-backups.sh
grep -q 'sha256' scripts/backup/pull-critical-backups.sh

printf 'Phase 05 backup contract: PASS\n'
