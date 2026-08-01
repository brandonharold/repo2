#!/usr/bin/env bash
#
# Snapshot / reset helper for the honeypot Linode.
#
# The intended lifecycle is: build → verify → snapshot a clean baseline → run
# a research window → restore the baseline. Never try to "clean" a honeypot
# you suspect was actually compromised; restore it.
#
# Requires: linode-cli, jq, and Backups enabled on the Linode
# (provision-linode.sh enables it at creation time).
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 snapshot <linode_id> [label]   Take a snapshot (replaces any existing one)
  $0 list <linode_id>               List available backups and snapshots
  $0 restore <linode_id> <backup_id>  Restore a snapshot over the Linode (destructive)

Note: Linode keeps exactly one manual snapshot per Linode — taking a new one
overwrites the previous one. Automatic daily/weekly backups are separate.
EOF
  exit 1
}

command -v linode-cli >/dev/null || { echo "Missing linode-cli" >&2; exit 1; }
command -v jq >/dev/null || { echo "Missing jq" >&2; exit 1; }

[[ $# -ge 2 ]] || usage
ACTION="$1"
LINODE_ID="$2"

case "$ACTION" in
  snapshot)
    LABEL="${3:-clean-baseline-$(date +%Y%m%d-%H%M)}"
    echo "This overwrites any existing manual snapshot for Linode ${LINODE_ID}."
    read -r -p "Take snapshot '${LABEL}'? [y/N] " reply
    [[ "$reply" == [yY] ]] || exit 1
    linode-cli linodes snapshot "$LINODE_ID" --label "$LABEL" --json --suppress-warnings \
      | jq -r '.[0] | "Snapshot started: id=\(.id) label=\(.label) status=\(.status)"'
    echo "Snapshots take several minutes. Check progress with: $0 list ${LINODE_ID}"
    ;;

  list)
    echo "== Manual snapshot =="
    linode-cli linodes backups-list "$LINODE_ID" --json --suppress-warnings \
      | jq -r '.[0].snapshot.current // empty
               | "id=\(.id) label=\(.label) status=\(.status) created=\(.created)"'
    echo "== Automatic backups =="
    linode-cli linodes backups-list "$LINODE_ID" --json --suppress-warnings \
      | jq -r '.[0].automatic[]? | "id=\(.id) type=\(.type) status=\(.status) created=\(.created)"'
    ;;

  restore)
    [[ $# -eq 3 ]] || usage
    BACKUP_ID="$3"
    echo "DESTRUCTIVE: this overwrites all disks on Linode ${LINODE_ID} with"
    echo "backup ${BACKUP_ID}. Any captured logs still on the box that you have"
    echo "not copied off will be lost."
    read -r -p "Type the Linode ID to confirm: " reply
    [[ "$reply" == "$LINODE_ID" ]] || { echo "Aborted."; exit 1; }
    linode-cli linodes backup-restore "$LINODE_ID" "$BACKUP_ID" \
      --linode_id "$LINODE_ID" --overwrite true --json --suppress-warnings >/dev/null
    echo "Restore started. Watch it in Cloud Manager or with:"
    echo "  linode-cli events list --json | jq '.[0:5]'"
    ;;

  *) usage ;;
esac
