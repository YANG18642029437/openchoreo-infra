#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
private_dir="$repo_root/.private/pki"
key="$private_dir/root-ca.key"
certificate="$private_dir/root-ca.crt"
kubeconfig="${KUBECONFIG:-$repo_root/.private/kubeconfigs/homelab-admin.yaml}"

install -d -m 0700 "$private_dir"

if [ ! -s "$key" ] || [ ! -s "$certificate" ]; then
  umask 077
  openssl req -x509 -new -nodes -newkey rsa:4096 -sha256 -days 3650 \
    -subj '/CN=OpenChoreo Homelab Root CA/O=OpenChoreo Homelab' \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -addext 'subjectKeyIdentifier=hash' \
    -keyout "$key" -out "$certificate" >/dev/null 2>&1
fi

chmod 0600 "$key" "$certificate"
kubectl --kubeconfig "$kubeconfig" wait --for=jsonpath='{.status.phase}'=Active \
  namespace/cert-manager --timeout=10m
kubectl --kubeconfig "$kubeconfig" -n cert-manager create secret tls homelab-root-ca \
  --cert="$certificate" --key="$key" --dry-run=client -o yaml \
  | kubectl --kubeconfig "$kubeconfig" apply -f - >/dev/null

printf 'root CA injection: PASS\n'
