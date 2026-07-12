#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
initializer="$repo_root/scripts/bootstrap/initialize-openbao.sh"

grep -q 'thunder.env' "$initializer"
grep -q 'openchoreo/thunder' "$initializer"

for key in \
  THUNDER_ADMIN_PASSWORD \
  THUNDER_DEVELOPER_PASSWORD \
  THUNDER_PLATFORM_ENGINEER_PASSWORD \
  THUNDER_SRE_PASSWORD \
  BACKSTAGE_BACKEND_SECRET \
  BACKSTAGE_CLIENT_SECRET \
  DEFAULT_APP_CLIENT_SECRET \
  RCA_AGENT_CLIENT_SECRET \
  SYSTEM_APP_CLIENT_SECRET \
  SERVICE_MCP_CLIENT_SECRET \
  WORKLOAD_PUBLISHER_CLIENT_SECRET \
  OBSERVER_READER_CLIENT_SECRET \
  FINOPS_AGENT_CLIENT_SECRET; do
  grep -q "$key" "$initializer"
done

if grep -R -E 'Admin@123|Dev@123|PE@123|SRE@123|backstage-portal-secret|openchoreo-system-app-secret' \
  "$repo_root" --exclude-dir=.git --exclude-dir=.private \
  --exclude='2026-07-10-phase-04-gitops-platform.md' \
  --exclude='thunder-secrets.sh'; then
  printf 'fixed Thunder development credential found outside protected storage\n' >&2
  exit 1
fi

printf 'Thunder secret bootstrap contract: PASS\n'
