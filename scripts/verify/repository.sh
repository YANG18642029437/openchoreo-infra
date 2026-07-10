#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

required=(
  README.md
  AGENTS.md
  SECURITY.md
  .gitignore
  .gitleaks.toml
  versions.lock.yaml
  inventory/hosts.yaml
  inventory/network.yaml
  inventory/proxmox.yaml
  scripts/lib/common.sh
  scripts/verify/secrets.sh
  scripts/verify/versions.sh
  scripts/audit/proxmox-readonly.sh
  scripts/audit/ip-addresses.sh
  scripts/audit/guest-disks.sh
  templates/operation-log.md
  logs/README.md
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing required file: %s\n' "$path" >&2
    exit 1
  }
done

for path in \
  .private/credentials/proxmox.env \
  .private/ssh/id_ed25519 \
  .private/kubeconfigs/admin.yaml \
  .private/terraform-state/terraform.tfstate \
  terraform/environments/homelab/terraform.tfvars; do
  git check-ignore -q "$path" || {
    printf 'sensitive path is not ignored: %s\n' "$path" >&2
    exit 1
  }
done

if git ls-files | rg '(^|/)(\.private/|.*\.tfstate($|\.)|.*\.tfvars$|kubeconfig|.*\.(pem|key)$)' >/dev/null; then
  printf 'tracked sensitive path detected\n' >&2
  exit 1
fi

printf 'repository contract: PASS\n'
