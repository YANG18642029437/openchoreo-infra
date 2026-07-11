#!/usr/bin/env bash
set -euo pipefail

: "${OPENCHOREO_SSH_KEY:?set OPENCHOREO_SSH_KEY}"
known_hosts="${OPENCHOREO_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"

ssh_options=(
  -i "$OPENCHOREO_SSH_KEY"
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$known_hosts"
)

ssh "${ssh_options[@]}" ubuntu@192.168.2.183 \
  'findmnt /srv/openchoreo && sudo exportfs -v && systemctl is-active nfs-server'

ssh "${ssh_options[@]}" ubuntu@192.168.2.180 '
  set -e
  tmp=$(mktemp -d)
  cleanup() {
    sudo umount "$tmp" 2>/dev/null || true
    rmdir "$tmp"
  }
  trap cleanup EXIT
  sudo mount -t nfs4 192.168.2.183:/ "$tmp"
  sudo touch "$tmp/shared/.write-test"
  sudo rm "$tmp/shared/.write-test"
'

printf 'nfs validation: PASS\n'
