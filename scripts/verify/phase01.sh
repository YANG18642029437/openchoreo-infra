#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

workspace_fingerprint() {
  {
    printf 'porcelain\0'
    git status --porcelain=v1 -z --untracked-files=all
    printf 'unstaged-diff\0'
    git diff --binary --no-ext-diff
    printf '\0cached-diff\0'
    git diff --cached --binary --no-ext-diff
    printf '\0untracked-content\0'
    while IFS= read -r -d '' path; do
      if [ -L "$path" ]; then
        path_type=symlink
        content_hash="$(git hash-object -- "$path")"
      elif [ -f "$path" ]; then
        path_type=file
        content_hash="$(git hash-object -- "$path")"
      else
        path_type=other
        content_hash="$(printf '%s' "$path_type" | git hash-object --stdin)"
      fi
      printf '%s\0%s\0%s\0' "$path" "$path_type" "$content_hash"
    done < <(git ls-files --others --exclude-standard -z)
  } | git hash-object --stdin
}

baseline_fingerprint="$(workspace_fingerprint)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openchoreo-phase01.XXXXXX")"
marker="$tmp_dir/probe-called"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ ! -e .private/evidence ]; then
  umask 077
  install -d -m 0700 .private/evidence
elif [ ! -d .private/evidence ]; then
  printf '.private/evidence exists but is not a directory\n' >&2
  exit 1
fi

./scripts/verify/repository.sh
./scripts/verify/secrets.sh
./scripts/verify/versions.sh

if command -v gitleaks >/dev/null 2>&1; then
  assurance='history=gitleaks worktree-index-untracked=regex'
else
  assurance='history=unscanned worktree-index-untracked=regex (REDUCED)'
fi

while IFS= read -r -d '' script; do
  bash -n "$script"
  test -x "$script" || {
    printf 'non-executable shell script: %s\n' "$script" >&2
    exit 1
  }
done < <(find scripts -type f -name '*.sh' -print0)

redaction_input='token=fixture-a
password="fixture b"
SECRET: fixture-c
https://example.invalid/?access_token=fixture-d&keep=yes
{"password":"fixture e","keep":true}
AWS_SECRET_ACCESS_KEY=fixture-f
CLIENT_SECRET_KEY="fixture g"
SECRET_KEY=fixture-h
API_TOKEN_VALUE=fixture-i
DB_PASSWORD_HASH=fixture-j'
redaction_output="$(printf '%s\n' "$redaction_input" | bash -c 'source scripts/lib/common.sh; redact')"
test "$(printf '%s\n' "$redaction_output" | awk '{ count += gsub(/\[redacted\]/, "") } END { print count + 0 }')" -eq 10
for fixture_value in fixture-a 'fixture b' fixture-c fixture-d 'fixture e' fixture-f 'fixture g' fixture-h fixture-i fixture-j; do
  if printf '%s\n' "$redaction_output" | grep -Fq "$fixture_value"; then
    printf 'redaction fixture leaked: %s\n' "$fixture_value" >&2
    exit 1
  fi
done

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
for command_name in ping arp route ip ssh; do
  stub_path="$stub_dir/$command_name"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$(basename "$0")" >> "$PHASE01_PROBE_MARKER"' \
    'exit 97' > "$stub_path"
  chmod +x "$stub_path"
done
export PHASE01_PROBE_MARKER="$marker"
ruby_path="$(command -v ruby || true)"
test -n "$ruby_path" || {
  printf 'missing command: ruby\n' >&2
  exit 1
}
ruby_dir="$(dirname "$ruby_path")"
probe_path="$stub_dir:$ruby_dir:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ip_output="$(PATH="$probe_path" IP_AUDIT_DRY_RUN=1 ./scripts/audit/ip-addresses.sh)"
expected_ip_output='audit_mode: dry_run
audit_target: 192.168.2.150
audit_target: 192.168.2.151
audit_target: 192.168.2.152
audit_target: 192.168.2.153
audit_target: 192.168.2.154
audit_target: 192.168.2.155
audit_target: 192.168.2.156
audit_target: 192.168.2.157
audit_target: 192.168.2.158
audit_target: 192.168.2.159
audit_target: 192.168.2.179
audit_target: 192.168.2.183'
test "$ip_output" = "$expected_ip_output"

guest_output="$(PATH="$probe_path" GUEST_AUDIT_DRY_RUN=1 ./scripts/audit/guest-disks.sh)"
expected_guest_output='audit_mode: dry_run
audit_target: root@192.168.2.180
audit_device: /dev/sdb
audit_target: root@192.168.2.181
audit_device: /dev/sdb
audit_target: root@192.168.2.182
audit_device: /dev/sdb'
test "$guest_output" = "$expected_guest_output"

PATH="$probe_path" bash -c '
  set -euo pipefail
  source scripts/audit/proxmox-readonly.sh
  validate_pve_host root@192.168.2.162
  unset PVE_SSH_IDENTITY_FILE
  build_ssh_args root@192.168.2.162
  expected=(
    ssh -F /dev/null
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=1
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=yes
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
    -- root@192.168.2.162
  )
  test "${#ssh_args[@]}" -eq "${#expected[@]}"
  index=0
  while [ "$index" -lt "${#expected[@]}" ]; do
    test "${ssh_args[$index]}" = "${expected[$index]}"
    index=$((index + 1))
  done
'

test ! -e "$marker" || {
  printf 'probe command executed during local gate:\n' >&2
  cat "$marker" >&2
  exit 1
}

ruby_bin="$ruby_path"

"$ruby_bin" -ryaml -ripaddr <<'RUBY'
hosts = YAML.safe_load(File.read('inventory/hosts.yaml'))
network = YAML.safe_load(File.read('inventory/network.yaml'))
proxmox = YAML.safe_load(File.read('inventory/proxmox.yaml'))
versions = YAML.safe_load(File.read('versions.lock.yaml'))
[hosts, network, proxmox, versions].each { |value| raise 'YAML root is not a mapping' unless value.is_a?(Hash) }

metadata = {'inventory_state' => 'desired', 'live_verification_required' => true}
raise 'host metadata mismatch' unless hosts.dig('all', 'vars').slice(*metadata.keys) == metadata
raise 'network metadata mismatch' unless network['metadata'] == metadata
raise 'Proxmox metadata mismatch' unless proxmox['metadata'] == metadata

host_entries = hosts.fetch('all').fetch('children').values.flat_map { |group| group.fetch('hosts').values }
host_ips = host_entries.map { |entry| IPAddr.new(entry.fetch('ansible_host')).to_s }
vm_ids = host_entries.map { |entry| entry.fetch('vm_id') }
raise 'host IPs must be unique IPv4 strings' unless host_ips.uniq.length == host_ips.length && host_ips.all? { |ip| IPAddr.new(ip).ipv4? }
raise 'VM IDs must be unique integers' unless vm_ids.uniq.length == vm_ids.length && vm_ids.all? { |id| id.is_a?(Integer) }

pool = network.fetch('metallb_pool')
raise 'MetalLB bounds mismatch' unless pool == {'start' => '192.168.2.150', 'end' => '192.168.2.159'}
pool_range = (IPAddr.new(pool.fetch('start')).to_i..IPAddr.new(pool.fetch('end')).to_i)
services = network.fetch('service_addresses').values
raise 'service IPs must be unique' unless services.uniq.length == services.length
raise 'service IP outside MetalLB pool' unless services.all? { |ip| pool_range.cover?(IPAddr.new(ip).to_i) }
vip = network.fetch('kubernetes_api_vip')
raise 'host/VIP/service overlap' unless (host_ips + [vip] + services).uniq.length == host_ips.length + 1 + services.length

expected_proxmox_keys = %w[metadata proxmox_endpoint node_name template_vm_id template_name system_datastore_id image_datastore_id backup_datastore_id nfs_data_datastore_id]
raise 'Proxmox key alignment mismatch' unless proxmox.keys.sort == expected_proxmox_keys.sort
raise 'Proxmox scalar types mismatch' unless proxmox.reject { |key, _| key == 'metadata' }.all? { |key, value| key == 'template_vm_id' ? value.is_a?(Integer) : value.is_a?(String) }
raise 'host VM ID collides with template VM ID' if vm_ids.include?(proxmox.fetch('template_vm_id'))

expected_version_sections = %w[generated_at terraform operating_system kubernetes openchoreo_compatibility platform]
raise 'version sections mismatch' unless versions.keys == expected_version_sections
raise 'generated_at must be a string' unless versions['generated_at'].is_a?(String)
versions.reject { |key, _| key == 'generated_at' }.each_value do |section|
  raise 'version section is not a mapping' unless section.is_a?(Hash)
  raise 'version leaf is not a string' unless section.values.all? { |value| value.is_a?(String) }
end
RUBY

"$ruby_bin" <<'RUBY'
text = File.read('README.md')
targets = text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten
relative = targets.reject { |target| target.match?(/\A(?:https?:|mailto:|#)/) }
missing = relative.reject do |target|
  path = target.split('#', 2).first
  !path.empty? && File.file?(path)
end
raise "missing README links: #{missing.join(', ')}" unless missing.empty?
raise 'planned Terraform path must be a code span' if text.match?(/\]\(terraform\//)
raise 'planned Ansible path must be a code span' if text.match?(/\]\(ansible\//)
raise 'planned Runbook path must be a code span' if text.match?(/\]\(runbooks\//)
RUBY

test -d .private/evidence
git check-ignore -q .private/evidence/
case "$(uname -s)" in
  Darwin) evidence_mode="$(stat -f '%Lp' .private/evidence)" ;;
  Linux) evidence_mode="$(stat -c '%a' .private/evidence)" ;;
  *) printf 'unsupported platform for stat: %s\n' "$(uname -s)" >&2; exit 1 ;;
esac
test "$evidence_mode" = 700

required=(
  README.md AGENTS.md SECURITY.md .gitignore .gitleaks.toml versions.lock.yaml
  inventory/hosts.yaml inventory/network.yaml inventory/proxmox.yaml
  scripts/lib/common.sh scripts/verify/repository.sh scripts/verify/secrets.sh
  scripts/verify/versions.sh scripts/verify/phase01.sh
  scripts/audit/proxmox-readonly.sh scripts/audit/ip-addresses.sh
  scripts/audit/guest-disks.sh templates/operation-log.md logs/README.md
)
git ls-files --error-unmatch "${required[@]}" >/dev/null
git diff --check
git diff --cached --check

final_fingerprint="$(workspace_fingerprint)"
test "$final_fingerprint" = "$baseline_fingerprint" || {
  printf 'phase01 gate changed workspace content\n' >&2
  printf 'baseline fingerprint: %s\nfinal fingerprint: %s\n' \
    "$baseline_fingerprint" "$final_fingerprint" >&2
  exit 1
}

printf 'secret assurance: %s\n' "$assurance"
printf 'phase01 local gate: PASS\n'
