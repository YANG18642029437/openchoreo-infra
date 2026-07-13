#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
defaults="$repo_root/ansible/roles/k3s_etcd_ssd/defaults/main.yml"
tasks="$repo_root/ansible/roles/k3s_etcd_ssd/tasks/main.yml"
playbook="$repo_root/ansible/playbooks/36-k3s-etcd-ssd.yml"
site="$repo_root/ansible/playbooks/site.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for path in "$defaults" "$tasks" "$playbook" "$site"; do
  test -f "$path" || fail "missing ${path#$repo_root/}"
done

require_literal() {
  grep -Fq -- "$2" "$1" || fail "${1#$repo_root/} missing: $2"
}

require_literal "$playbook" 'hosts: k3s_servers'
require_literal "$playbook" 'serial: 1'
require_literal "$playbook" 'any_errors_fatal: true'
require_literal "$playbook" 'role: k3s_etcd_ssd'
require_literal "$playbook" 'ansible_play_hosts_all | length == 1'
require_literal "$defaults" 'k3s_etcd_ssd_allow_format: false'
require_literal "$defaults" 'k3s_etcd_ssd_mount_path: /var/lib/rancher/k3s-ssd'
require_literal "$defaults" 'k3s_etcd_ssd_bind_path: /var/lib/rancher/k3s/server/db'

for contract in 'lsblk' 'findmnt' 'k3s etcd-snapshot save' \
  'community.general.filesystem' 'ansible.posix.mount' 'rsync' \
  'systemd_service' 'bind,x-systemd.requires-mounts-for=' \
  'kubectl' '--for=condition=Ready' '/readyz?verbose'; do
  require_literal "$tasks" "$contract"
done

if grep -Fq '36-k3s-etcd-ssd.yml' "$site"; then
  fail 'destructive migration playbook must not be imported by site.yml'
fi

require_literal "$tasks" 'k3s_etcd_ssd_candidates | length == 1'
require_literal "$tasks" 'k3s_etcd_ssd_allow_format | bool'
require_literal "$tasks" 'inventory_hostname == ansible_play_hosts_all[0]'

printf 'PASS: K3s etcd SSD migration contract\n'
