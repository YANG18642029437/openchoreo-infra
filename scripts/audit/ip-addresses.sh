#!/usr/bin/env bash
set -euo pipefail

targets=(
  192.168.2.170
  192.168.2.171
  192.168.2.172
  192.168.2.173
  192.168.2.174
  192.168.2.175
  192.168.2.176
  192.168.2.177
  192.168.2.178
  192.168.2.179
  192.168.2.183
)

busy=0
for ip in "${targets[@]}"; do
  if ping -c 1 -W 1000 "$ip" >/dev/null 2>&1; then
    printf 'BUSY ping %s\n' "$ip"
    busy=1
    continue
  fi
  if arp -an | rg -F "($ip)" >/dev/null 2>&1; then
    printf 'BUSY arp %s\n' "$ip"
    busy=1
    continue
  fi
  printf 'NO_RESPONSE %s\n' "$ip"
done

exit "$busy"
