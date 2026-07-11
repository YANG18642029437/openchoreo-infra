#!/usr/bin/env bash
set -euo pipefail

: "${OPENCHOREO_SSH_KEY:?set OPENCHOREO_SSH_KEY}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
known_hosts="${OPENCHOREO_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
kubeconfig="$repo_root/.private/kubeconfigs/homelab-admin.yaml"

install -d -m 0700 "$repo_root/.private/kubeconfigs"
umask 077
ssh -i "$OPENCHOREO_SSH_KEY" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
  ubuntu@192.168.2.180 'sudo cat /etc/rancher/k3s/k3s.yaml' |
  sed 's#https://127.0.0.1:6443#https://192.168.2.179:6443#' > "$kubeconfig"

KUBECONFIG="$kubeconfig" kubectl get nodes
