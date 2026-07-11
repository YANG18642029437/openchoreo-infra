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
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing Ansible file: %s\n' "$path" >&2
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
