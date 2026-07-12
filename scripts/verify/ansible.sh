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
  ansible/playbooks/15-egress-gateway.yml
  ansible/playbooks/16-egress-clients.yml
  ansible/playbooks/20-nfs.yml
  ansible/playbooks/30-k3s.yml
  ansible/playbooks/40-argocd.yml
  ansible/playbooks/site.yml
  ansible/roles/common/defaults/main.yml
  ansible/roles/common/tasks/main.yml
  ansible/roles/common/handlers/main.yml
  ansible/roles/egress_gateway/defaults/main.yml
  ansible/roles/egress_gateway/tasks/main.yml
  ansible/roles/egress_gateway/handlers/main.yml
  ansible/roles/egress_gateway/templates/sing-box.service.j2
  ansible/roles/egress_client/defaults/main.yml
  ansible/roles/egress_client/tasks/main.yml
  ansible/roles/egress_client/handlers/main.yml
  ansible/roles/egress_client/templates/proxy.conf.j2
  ansible/roles/nfs/defaults/main.yml
  ansible/roles/nfs/tasks/main.yml
  ansible/roles/nfs/handlers/main.yml
  ansible/roles/nfs/templates/exports.j2
  ansible/roles/k3s/defaults/main.yml
  ansible/roles/k3s/tasks/main.yml
  ansible/roles/k3s/templates/config.yaml.j2
  ansible/roles/kube_vip/defaults/main.yml
  ansible/roles/kube_vip/tasks/main.yml
  ansible/roles/kube_vip/templates/kube-vip.yaml.j2
  ansible/roles/cilium/defaults/main.yml
  ansible/roles/cilium/tasks/main.yml
  ansible/roles/cilium/templates/cilium-helmchart.yaml.j2
  ansible/roles/argocd/defaults/main.yml
  ansible/roles/argocd/tasks/main.yml
  ansible/roles/argocd/tasks/distribute_images.yml
  runbooks/20-ansible-bootstrap.md
  runbooks/21-k3s-recovery.md
  scripts/bootstrap/export-kubeconfig.sh
  scripts/verify/cluster-foundation.sh
  scripts/verify/nfs.sh
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing Ansible file: %s\n' "$path" >&2
    exit 1
  }
done

for contract in SING_BOX_ARCHIVE SING_BOX_CONFIG_PATH sing-box.service \
  egress_gateways; do
  grep -R -F "$contract" ansible/roles/egress_gateway \
    ansible/playbooks/15-egress-gateway.yml inventory/hosts.yaml >/dev/null || {
    printf 'missing egress gateway contract: %s\n' "$contract" >&2
    exit 1
  }
done

for contract in EGRESS_PROXY_URL HTTPS_PROXY NO_PROXY k3s.service.d; do
  grep -R -F "$contract" ansible/roles/egress_client \
    ansible/playbooks/16-egress-clients.yml >/dev/null || {
    printf 'missing egress client contract: %s\n' "$contract" >&2
    exit 1
  }
done

for contract in kubernetes.core.helm redis-ha ARGOCD_IMAGE_FILES \
  argocd-server imagePullPolicy; do
  grep -R -F "$contract" ansible/roles/argocd ansible/playbooks/40-argocd.yml \
    >/dev/null || {
    printf 'missing Argo CD bootstrap contract: %s\n' "$contract" >&2
    exit 1
  }
done

for contract in cluster-init flannel-backend disable-network-policy \
  192.168.2.179 ghcr.io/kube-vip/kube-vip static/charts/cilium; do
  grep -R -F "$contract" ansible/roles/k3s ansible/roles/kube_vip \
    ansible/roles/cilium scripts/bootstrap scripts/verify/cluster-foundation.sh \
    >/dev/null || {
    printf 'missing K3s foundation contract: %s\n' "$contract" >&2
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
