#!/usr/bin/env bash
set -euo pipefail

backup_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backup_ssh_user="${OPENCHOREO_SSH_USER:-ubuntu}"
backup_ssh_key="${OPENCHOREO_SSH_KEY:-$backup_repo_root/.private/ssh/openchoreo_ed25519}"
backup_known_hosts="${OPENCHOREO_KNOWN_HOSTS:-$backup_repo_root/.private/ssh/known_hosts}"
backup_nfs_host="${OPENCHOREO_NFS_HOST:-192.168.2.183}"
backup_nfs_root="${OPENCHOREO_NFS_ROOT:-/srv/openchoreo/backups}"
backup_kubeconfig="${KUBECONFIG:-$backup_repo_root/.private/kubeconfigs/homelab-admin-direct.yaml}"

backup_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
backup_require_command() { command -v "$1" >/dev/null 2>&1 || backup_die "missing command: $1"; }
backup_require_file() { test -f "$1" || backup_die "missing file: $1"; }
backup_validate_kind() { [[ "$1" =~ ^(etcd|openbao|harbor-db)$ ]] || backup_die 'invalid backup kind'; }

backup_ssh() {
  local host="$1"; shift
  ssh -i "$backup_ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o "UserKnownHostsFile=$backup_known_hosts" "$backup_ssh_user@$host" "$@"
}

backup_store_on_nfs() {
  local kind="$1" source="$2" filename
  backup_validate_kind "$kind"
  backup_require_file "$source"
  test -s "$source" || backup_die "backup is empty: $source"
  filename="$(basename "$source")"
  [[ "$filename" =~ ^[A-Za-z0-9._-]+$ ]] || backup_die 'unsafe backup filename'
  scp -q -i "$backup_ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o "UserKnownHostsFile=$backup_known_hosts" "$source" \
    "$backup_ssh_user@$backup_nfs_host:/tmp/$filename"
  backup_ssh "$backup_nfs_host" \
    "sudo install -o nobody -g nogroup -m 0640 /tmp/$filename $backup_nfs_root/$kind/$filename && rm -f /tmp/$filename"
  printf 'BACKUP_STORED kind=%s file=%s\n' "$kind" "$filename"
}

backup_init() {
  umask 077
  backup_require_command ssh
  backup_require_command scp
  backup_require_command kubectl
  backup_require_file "$backup_ssh_key"
  backup_require_file "$backup_known_hosts"
  backup_require_file "$backup_kubeconfig"
  export KUBECONFIG="$backup_kubeconfig"
}
