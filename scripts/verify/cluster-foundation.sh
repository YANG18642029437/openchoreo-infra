#!/usr/bin/env bash
set -euo pipefail

: "${OPENCHOREO_SSH_KEY:?set OPENCHOREO_SSH_KEY}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
known_hosts="${OPENCHOREO_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
export KUBECONFIG="${KUBECONFIG:-$repo_root/.private/kubeconfigs/homelab-admin.yaml}"

ready_nodes="$(kubectl get nodes --no-headers | awk '$2 == "Ready" { count++ } END { print count + 0 }')"
test "$ready_nodes" -eq 3
kubectl -n kube-system rollout status daemonset/cilium --timeout=10m
kubectl -n kube-system rollout status daemonset/kube-vip-ds --timeout=5m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=10m
api_status="$(curl --silent --show-error --insecure --output /dev/null \
  --write-out '%{http_code}' https://192.168.2.179:6443/livez)"
case "$api_status" in
  200|401) ;;
  *)
    printf 'unexpected API VIP status: %s\n' "$api_status" >&2
    exit 1
    ;;
esac

if kubectl -n kube-system get pods -o name | grep -E '/(traefik|svclb)'; then
  printf 'unexpected Traefik or ServiceLB pod found\n' >&2
  exit 1
fi

ssh -i "$OPENCHOREO_SSH_KEY" -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
  ubuntu@192.168.2.180 'sudo k3s etcd-snapshot ls'

printf 'cluster foundation validation: PASS\n'
