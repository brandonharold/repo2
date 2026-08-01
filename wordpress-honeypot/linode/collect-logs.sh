#!/usr/bin/env bash
#
# Pull captured honeypot logs off the Linode to your workstation before a
# snapshot restore (a restore destroys anything left on the box).
#
# Usage: ./collect-logs.sh root@203.0.113.10 [output_dir]
set -euo pipefail

TARGET="${1:?Usage: $0 user@host [output_dir]}"
OUTDIR="${2:-./captures/$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTDIR"

echo "==> Collecting from ${TARGET} into ${OUTDIR}"

# shellcheck disable=SC2029  # remote-side expansion is intended
ssh "$TARGET" 'tar -czf - \
    /var/log/wp-honeypot/ \
    /var/log/nginx/wp-honeypot-*.log* \
    /var/log/fail2ban.log* \
    /var/log/auth.log* \
    2>/dev/null' >"${OUTDIR}/honeypot-logs.tar.gz" || true

if [[ ! -s "${OUTDIR}/honeypot-logs.tar.gz" ]]; then
  echo "Collection produced an empty archive — check SSH access and paths." >&2
  exit 1
fi

# A quick at-a-glance summary of what was captured.
tar -xzOf "${OUTDIR}/honeypot-logs.tar.gz" --wildcards 'var/log/wp-honeypot/events.log' 2>/dev/null \
  | jq -rs '
      "Events captured: \(length)",
      "By type:",
      (group_by(.type)[] | "  \(.[0].type): \(length)"),
      "Distinct source IPs: \([.[].ip] | unique | length)"
    ' 2>/dev/null || echo "(install jq for a capture summary)"

echo "==> Saved ${OUTDIR}/honeypot-logs.tar.gz"
echo "    Treat captured IPs as personal data under your local law."
