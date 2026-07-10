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

tracked_files="$(git ls-files)"
if tracked_sensitive_paths="$(grep -E '(^|/)(\.private/|.*\.tfstate($|\.)|.*\.tfvars$|kubeconfig|.*\.(pem|key)$)' <<<"$tracked_files")"; then
  scanner_status=0
else
  scanner_status=$?
fi

case "$scanner_status" in
  0)
    first_sensitive_path="${tracked_sensitive_paths%%$'\n'*}"
    printf 'tracked sensitive path detected: %s\n' "$first_sensitive_path" >&2
    exit 1
    ;;
  1)
    ;;
  *)
    printf 'failed to scan tracked files for sensitive paths (grep exit %s)\n' "$scanner_status" >&2
    exit 1
    ;;
esac

printf 'repository contract: PASS\n'
