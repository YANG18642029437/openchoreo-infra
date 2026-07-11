#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"

required=(
  ansible/ansible.cfg
  ansible/requirements.yml
  inventory/hosts.yaml
  ansible/group_vars/all.yml
  ansible/playbooks/00-preflight.yml
  ansible/playbooks/10-common.yml
  ansible/playbooks/20-nfs.yml
  ansible/playbooks/30-k3s.yml
  ansible/playbooks/40-argocd.yml
  ansible/playbooks/site.yml
  ansible/roles/common/defaults/main.yml
  ansible/roles/common/tasks/main.yml
  ansible/roles/common/handlers/main.yml
  ansible/roles/nfs/defaults/main.yml
  ansible/roles/nfs/tasks/main.yml
  ansible/roles/nfs/handlers/main.yml
  ansible/roles/nfs/templates/exports.j2
  scripts/verify/nfs.sh
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing Ansible file: %s\n' "$path" >&2
    exit 1
  }
done

grep -F "Create the NFS exports directory" ansible/roles/nfs/tasks/main.yml >/dev/null || {
  printf 'missing NFS exports directory creation task\n' >&2
  exit 1
}

for contract in nfs_allow_format community.general.filesystem \
  nfs-kernel-server xfsprogs exportfs; do
  grep -R -F "$contract" ansible/roles/nfs scripts/verify/nfs.sh >/dev/null || {
    printf 'missing NFS safety contract: %s\n' "$contract" >&2
    exit 1
  }
done

for contract in qemu-guest-agent nfs-common open-iscsi overlay br_netfilter \
  net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables \
  net.ipv4.ip_forward; do
  grep -R -F "$contract" ansible/roles/common >/dev/null || {
    printf 'missing common baseline contract: %s\n' "$contract" >&2
    exit 1
  }
done

ansible-config dump --only-changed | grep -F "$repo_root/ansible/roles"
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/site.yml --syntax-check
if command -v ansible-lint >/dev/null 2>&1; then
  ansible-lint ansible/
fi
printf 'ansible static validation: PASS\n'
