#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bootstrap="$repo_root/scripts/bootstrap/initialize-openbao.sh"

grep -q 'observability.env' "$bootstrap"
grep -q 'OPENSEARCH_USERNAME' "$bootstrap"
grep -q 'OPENSEARCH_PASSWORD' "$bootstrap"
grep -q 'bao kv put openchoreo/observability' "$bootstrap"

echo 'OpenBao observability secret bootstrap contract: PASS'
