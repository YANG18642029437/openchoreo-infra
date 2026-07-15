#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
prepare="$repo_root/scripts/prepare/agent-platform-secrets.sh"
bootstrap="$repo_root/scripts/bootstrap/initialize-agent-platform-secrets.sh"

test -x "$prepare"
test -x "$bootstrap"
bash -n "$prepare"
bash -n "$bootstrap"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-platform-secrets.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
secret_file="$tmp_dir/agent-platform.env"

first_output="$(AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
test -s "$secret_file"
grep -q '^MINIO_ROOT_USER=' "$secret_file"
grep -q '^MINIO_ROOT_PASSWORD=' "$secret_file"
grep -q '^REDIS_PASSWORD=' "$secret_file"
case "$(uname -s)" in
  Darwin) file_mode="$(stat -f '%Lp' "$secret_file")" ;;
  Linux) file_mode="$(stat -c '%a' "$secret_file")" ;;
  *) exit 1 ;;
esac
test "$file_mode" = 600

set -a
source "$secret_file"
set +a
test "$MINIO_ROOT_USER" = agent-platform
test "${#MINIO_ROOT_PASSWORD}" -ge 32
test "${#REDIS_PASSWORD}" -ge 32
if printf '%s\n' "$first_output" | grep -Fq "$MINIO_ROOT_PASSWORD"; then
  printf 'prepare script leaked generated password\n' >&2
  exit 1
fi
if printf '%s\n' "$first_output" | grep -Fq "$REDIS_PASSWORD"; then
  printf 'prepare script leaked generated Redis password\n' >&2
  exit 1
fi

first_hash="$(shasum -a 256 "$secret_file" | awk '{print $1}')"
second_output="$(AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
second_hash="$(shasum -a 256 "$secret_file" | awk '{print $1}')"
test "$first_hash" = "$second_hash"
if printf '%s\n' "$second_output" | grep -Fq "$MINIO_ROOT_PASSWORD"; then
  printf 'prepare rerun leaked existing password\n' >&2
  exit 1
fi
if printf '%s\n' "$second_output" | grep -Fq "$REDIS_PASSWORD"; then
  printf 'prepare rerun leaked existing Redis password\n' >&2
  exit 1
fi

fake_repo="$tmp_dir/fake-repo"
mkdir -p "$fake_repo/scripts/prepare"
cp "$prepare" "$fake_repo/scripts/prepare/agent-platform-secrets.sh"
"$fake_repo/scripts/prepare/agent-platform-secrets.sh" >/dev/null
test -s "$fake_repo/.private/openbao/agent-platform.env" || {
  printf 'prepare default path is not rooted at the repository\n' >&2
  exit 1
}
test ! -e "$fake_repo/scripts/.private/openbao/agent-platform.env"

grep -Fq 'openchoreo/agent-platform/development/minio' "$bootstrap"
grep -Fq 'openchoreo/agent-platform/development/redis' "$bootstrap"
grep -Fq 'root_user' "$bootstrap"
grep -Fq 'root_password' "$bootstrap"
grep -Fq 'REDIS_PASSWORD' "$bootstrap"
grep -Fq 'agent-platform.env' "$bootstrap"

printf 'Agent Platform local secret contract: PASS\n'
