#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init

node_host="${ETCD_SNAPSHOT_NODE:-192.168.2.180}"
node_name="${ETCD_SNAPSHOT_NODE_NAME:-ocp-node-01}"
stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
name="phase05-${node_name}-${stamp}"
snapshot_dir="/var/lib/rancher/k3s/server/db/snapshots"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
local_file="$tmp_dir/${name}.snapshot"

backup_ssh "$node_host" "sudo k3s etcd-snapshot save --name $name >/dev/null"
remote_path="$(backup_ssh "$node_host" "sudo find $snapshot_dir -maxdepth 1 -type f -name '$name-*' -printf '%T@ %p\\n' | sort -nr | head -1 | cut -d' ' -f2-")"
[[ "$remote_path" =~ ^/var/lib/rancher/k3s/server/db/snapshots/[A-Za-z0-9._-]+$ ]] || backup_die 'K3s did not return a safe snapshot path'
backup_ssh "$node_host" "sudo test -s $remote_path && sudo cat $remote_path" >"$local_file"
backup_store_on_nfs etcd "$local_file"
