#!/usr/bin/env bash
set -euo pipefail

resolver=/etc/resolver/openchoreo.home.arpa
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf 'nameserver 192.168.2.157\nport 53\ntimeout 5\n' >"$tmp"
sudo install -d -m 0755 /etc/resolver
sudo install -m 0644 "$tmp" "$resolver"
dscacheutil -flushcache
sudo killall -HUP mDNSResponder
dig +short harbor.openchoreo.home.arpa
