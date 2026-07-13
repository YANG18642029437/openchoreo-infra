#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s <terraform-plan-file>\n' "$0" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tf_dir="$repo_root/terraform/environments/homelab"
plan_file="$1"

test -f "$plan_file" || {
  printf 'missing Terraform plan: %s\n' "$plan_file" >&2
  exit 1
}
command -v terraform >/dev/null 2>&1 || {
  printf 'missing command: terraform\n' >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  printf 'missing command: python3\n' >&2
  exit 1
}

terraform -chdir="$tf_dir" show -json "$plan_file" |
  python3 -c '
import json, sys

payload = json.load(sys.stdin)
expected = {
    "module.k3s_nodes[\"ocp-node-01\"].proxmox_virtual_environment_vm.this",
    "module.k3s_nodes[\"ocp-node-02\"].proxmox_virtual_environment_vm.this",
    "module.k3s_nodes[\"ocp-node-03\"].proxmox_virtual_environment_vm.this",
}
changes = payload.get("resource_changes")
if not isinstance(changes, list):
    raise SystemExit("plan has no resource_changes array")

changed = []
for item in changes:
    actions = item.get("change", {}).get("actions")
    if actions == ["no-op"]:
        continue
    address = item.get("address")
    if address not in expected or actions != ["update"]:
        raise SystemExit(f"unexpected Terraform change: {address} actions={actions}")
    before = item["change"].get("before") or {}
    after = item["change"].get("after") or {}
    before_disks = before.get("disk") or []
    after_disks = after.get("disk") or []
    before_by_interface = {disk.get("interface"): disk for disk in before_disks}
    after_by_interface = {disk.get("interface"): disk for disk in after_disks}
    if None in before_by_interface or None in after_by_interface:
        raise SystemExit(f"{address} has a disk without an interface")
    if "scsi1" in before_by_interface:
        raise SystemExit(f"{address} already has scsi1 before this plan")
    disk = after_by_interface.get("scsi1")
    if disk is None:
        raise SystemExit(f"{address} does not add scsi1")
    preserved_before = before_by_interface
    preserved_after = {
        interface: value
        for interface, value in after_by_interface.items()
        if interface != "scsi1"
    }
    if preserved_after != preserved_before:
        raise SystemExit(f"{address} changes an existing disk")
    expected_disk = {
        "datastore_id": "SSD1",
        "interface": "scsi1",
        "size": 20,
        "iothread": True,
        "discard": "on",
        "ssd": True,
    }
    for key, value in expected_disk.items():
        if disk.get(key) != value:
            raise SystemExit(f"{address} invalid {key}: {disk.get(key)!r}")
    changed.append(address)

if set(changed) != expected:
    raise SystemExit(f"changed VM set mismatch: {sorted(changed)}")
print("Terraform etcd SSD plan: PASS")
'
