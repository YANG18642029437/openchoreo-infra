#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
base_url="https://cloud-images.ubuntu.com/noble/current"
image="noble-server-cloudimg-amd64.img"
private_dir="$repo_root/.private/credentials"
env_file="$private_dir/terraform.env"
temp_file=""

cleanup() {
  if [ -n "$temp_file" ]; then
    rm -f "$temp_file"
  fi
}
trap cleanup EXIT

command -v curl >/dev/null 2>&1 || {
  printf 'ERROR: missing command: curl\n' >&2
  exit 1
}
command -v awk >/dev/null 2>&1 || {
  printf 'ERROR: missing command: awk\n' >&2
  exit 1
}

install -d -m 0700 "$private_dir"
checksum="$(
  curl -fsSL "$base_url/SHA256SUMS" |
    awk -v image="$image" '$2 == image || $2 == "*" image { print $1 }'
)"

if [ "${#checksum}" -ne 64 ]; then
  printf 'ERROR: expected exactly one 64-character SHA-256 digest for %s\n' "$image" >&2
  exit 1
fi
case "$checksum" in
  *[!0-9a-f]*)
    printf 'ERROR: Ubuntu image checksum is not lowercase hexadecimal\n' >&2
    exit 1
    ;;
esac

umask 077
temp_file="$private_dir/.terraform.env.tmp.$$"
{
  printf 'export TF_VAR_ubuntu_image_checksum=%q\n' "$checksum"
  printf 'export TF_VAR_ssh_public_key_path=%q\n' \
    "../../../.private/ssh/openchoreo_ed25519.pub"
} >"$temp_file"
chmod 0600 "$temp_file"
mv "$temp_file" "$env_file"
temp_file=""

printf 'Terraform image variables written to protected credentials file.\n'
