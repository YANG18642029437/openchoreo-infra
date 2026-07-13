#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

playbook=ansible/playbooks/17-internal-services-clients.yml
defaults=ansible/roles/internal_services_client/defaults/main.yml
tasks=ansible/roles/internal_services_client/tasks/main.yml
handlers=ansible/roles/internal_services_client/handlers/main.yml
template=ansible/roles/internal_services_client/templates/openchoreo-resolved.conf.j2

for path in "$playbook" "$defaults" "$tasks" "$handlers" "$template"; do
  test -f "$path" || { printf 'missing internal services client file: %s\n' "$path" >&2; exit 1; }
done

grep -q 'hosts: k3s_servers' "$playbook"
grep -q 'serial: 1' "$playbook"
grep -q 'any_errors_fatal: true' "$playbook"
grep -q '192.168.2.157' "$defaults"
grep -q 'Domains=~' "$template"
grep -q 'update-ca-certificates' "$handlers"
grep -q 'openchoreo-homelab-root-ca.crt' "$tasks"
grep -q 'resolvectl query harbor.openchoreo.home.arpa' "$tasks"
grep -q 'Restart K3s' "$handlers"

printf 'internal services client contract: PASS\n'
