#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

patterns='BEGIN [A-Z ]*PRIVATE KEY'
patterns+='|client-key-''data:'
patterns+='|client-certificate-''data:'
patterns+='|api[_-]?token[[:space:]]*[:=][[:space:]]*[^$<{]'

if git grep -n -E "$patterns" -- . \
  ':(exclude)*.example' \
  ':(exclude)docs/superpowers/**'; then
  printf 'possible secret detected in tracked files\n' >&2
  exit 1
fi

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --redact --no-banner
else
  printf 'gitleaks unavailable; regex scan only\n'
fi

printf 'secret boundary: PASS\n'
