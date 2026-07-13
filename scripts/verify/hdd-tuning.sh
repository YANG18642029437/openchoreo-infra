#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playbook="$repo_root/ansible/playbooks/35-k3s-hdd-tuning.yml"
site_playbook="$repo_root/ansible/playbooks/site.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local value="$2"

  grep -Fq -- "$value" "$file" ||
    fail "$(basename "$file") missing required contract: $value"
}

[[ -f "$playbook" ]] || fail "missing ansible/playbooks/35-k3s-hdd-tuning.yml"
[[ -f "$site_playbook" ]] || fail "missing ansible/playbooks/site.yml"

require_literal "$playbook" 'hosts: k3s_servers'
require_literal "$playbook" 'serial: 1'
require_literal "$playbook" 'any_errors_fatal: true'
require_literal "$playbook" 'defaults,commit=30,errors=remount-ro'
require_literal "$playbook" 'mount -o remount,nodiscard /'
require_literal "$playbook" 'name: fstrim.timer'
require_literal "$playbook" 'enabled: true'
require_literal "$playbook" 'state: started'
require_literal "$playbook" 'kubectl'
require_literal "$playbook" '--for=condition=Ready'
require_literal "$site_playbook" 'import_playbook: 35-k3s-hdd-tuning.yml'

if grep -Eq '^[[:space:]]*hosts:[[:space:]]+all([[:space:]]|$)' "$playbook"; then
  fail 'HDD tuning must not target all inventory hosts'
fi

if grep -Ein '\b(mkfs|wipefs|parted|fdisk|umount)\b|terraform[[:space:]]+apply|/api2/json' "$playbook"; then
  fail 'HDD tuning playbook contains a forbidden disk or PVE mutation command'
fi

printf 'PASS: K3s HDD tuning contract\n'
