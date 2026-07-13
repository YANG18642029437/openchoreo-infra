#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/backup-common.sh"
backup_init

mode="${DRILL_MODE:-verify}"
target_node="${DRILL_NODE_NAME:-ocp-node-03}"
target_host="${DRILL_NODE_HOST:-192.168.2.182}"
gitops_repo="${OPENCHOREO_GITOPS_REPO:-$repo_root/../openchoreo-gitops}"

test "$mode" = verify || test "$mode" = execute || backup_die 'DRILL_MODE must be verify or execute'
"$repo_root/scripts/verify/backup-artifacts.sh" >/dev/null
printf 'BACKUP_GATE PASS\n'

kubectl get --raw=/readyz | grep -qx ok
test "$(kubectl get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')" = 3
kubectl get xpostgresql -A -o json | jq -e \
  '[.items[] | select(.metadata.name | startswith("r-phase05-postgresql-")) | .status.ready] | length == 3 and all' >/dev/null
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type --no-headers
printf 'BASELINE PASS\n'

stopped=0
recover_target() {
  if test "$stopped" = 1; then
    printf 'RECOVERY_GUARD starting=%s\n' "$target_node" >&2
    backup_ssh "$target_host" 'sudo systemctl start k3s'
    kubectl wait --for=condition=Ready "node/$target_node" --timeout=10m >/dev/null || true
  fi
}
trap recover_target EXIT

if test "$mode" = execute; then
  backup_ssh "$target_host" 'sudo systemctl stop k3s'
  stopped=1
  printf 'NODE_STOPPED node=%s\n' "$target_node"
  for _ in $(seq 1 30); do
    status="$(kubectl get node "$target_node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
    test "$status" = False -o "$status" = Unknown && break
    sleep 5
  done
  status="$(kubectl get node "$target_node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  test "$status" = False -o "$status" = Unknown || backup_die "$target_node did not become NotReady"
  printf 'NODE_NOT_READY node=%s\n' "$target_node"

  for _ in 1 2 3; do
    kubectl get --raw=/readyz | grep -qx ok
    for environment in development staging production; do
      curl --noproxy '*' -fsS --max-time 10 \
        "http://${environment}-default.apps.openchoreo.home.arpa/phase05-smoke-http/healthz" \
        | jq -e '.status == "ok"' >/dev/null
    done
    sleep 2
  done
  printf 'OUTAGE_PROBES PASS\n'

  backup_ssh "$target_host" 'sudo systemctl start k3s'
  printf 'NODE_STARTED node=%s\n' "$target_node"
  kubectl wait --for=condition=Ready "node/$target_node" --timeout=10m >/dev/null
  stopped=0
  printf 'NODE_READY node=%s\n' "$target_node"
fi

kubectl -n kube-system rollout status daemonset/cilium --timeout=10m >/dev/null
printf 'CILIUM_READY PASS\n'
kubectl get --raw=/readyz | grep -qx ok
KUBECONFIG="$backup_kubeconfig" "$gitops_repo/scripts/verify/end-to-end.sh" >/dev/null
printf 'END_TO_END PASS\n'

printf 'Phase 05 disaster recovery validation: PASS mode=%s node=%s\n' "$mode" "$target_node"
