#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

baseline_status="$(git status --porcelain --untracked-files=all)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openchoreo-phase01.XXXXXX")"
marker="$tmp_dir/probe-called"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

./scripts/verify/repository.sh
./scripts/verify/secrets.sh
./scripts/verify/versions.sh

if command -v gitleaks >/dev/null 2>&1; then
  assurance='FULL'
else
  assurance='REDUCED regex-only (gitleaks unavailable)'
fi

while IFS= read -r -d '' script; do
  bash -n "$script"
  test -x "$script" || {
    printf 'non-executable shell script: %s\n' "$script" >&2
    exit 1
  }
done < <(find scripts -type f -name '*.sh' -print0)

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
probe_path="$stub_dir:/usr/bin:/bin:/usr/sbin:/sbin"

ip_output="$(PATH="$probe_path" IP_AUDIT_DRY_RUN=1 ./scripts/audit/ip-addresses.sh)"
test "$(printf '%s\n' "$ip_output" | grep -c '^audit_target: ')" -eq 11
test "$(printf '%s\n' "$ip_output" | grep -c '^audit_mode: dry_run$')" -eq 1

guest_output="$(PATH="$probe_path" GUEST_AUDIT_DRY_RUN=1 ./scripts/audit/guest-disks.sh)"
test "$(printf '%s\n' "$guest_output" | grep -c '^audit_target: ')" -eq 3
test "$(printf '%s\n' "$guest_output" | grep -c '^audit_device: /dev/sdb$')" -eq 3
test "$(printf '%s\n' "$guest_output" | grep -c '^audit_mode: dry_run$')" -eq 1

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

if [ -x /usr/bin/ruby ]; then
  ruby_bin=/usr/bin/ruby
elif command -v ruby >/dev/null 2>&1; then
  ruby_bin="$(command -v ruby)"
else
  printf 'missing command: ruby\n' >&2
  exit 1
fi

"$ruby_bin" -ryaml <<'RUBY'
%w[inventory/hosts.yaml inventory/network.yaml inventory/proxmox.yaml versions.lock.yaml].each do |path|
  value = YAML.safe_load(File.read(path))
  raise "#{path} is not a mapping" unless value.is_a?(Hash)
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

final_status="$(git status --porcelain --untracked-files=all)"
test "$final_status" = "$baseline_status" || {
  printf 'phase01 gate changed worktree status\n' >&2
  printf '%s\n' '--- baseline ---' "$baseline_status" '--- final ---' "$final_status" >&2
  exit 1
}

printf 'secret assurance: %s\n' "$assurance"
printf 'phase01 local gate: PASS\n'
