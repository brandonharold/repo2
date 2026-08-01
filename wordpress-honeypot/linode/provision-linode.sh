#!/usr/bin/env bash
#
# End-to-end provisioning of the honeypot on Linode/Akamai.
#
# Creates (1) a private StackScript from stackscript.sh, (2) a Linode running
# it, and (3) an egress-restricted Cloud Firewall attached to that Linode.
#
# Run this from your workstation, not on the server.
#
# Requires: linode-cli (`pip install linode-cli`), jq, curl, and a Linode API
# token with read/write on Linodes, StackScripts, and Firewalls:
#   export LINODE_TOKEN=...
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration (override via environment) ---
LABEL="${LABEL:-wp-honeypot}"
REGION="${REGION:-us-east}"
TYPE="${TYPE:-g6-nanode-1}"          # Nanode 1GB is ample for this workload
IMAGE="${IMAGE:-linode/ubuntu24.04}"

DOMAIN="${DOMAIN:?Set DOMAIN, e.g. export DOMAIN=honeypot.example.com}"
SITE_TITLE="${SITE_TITLE:-Summit Business Solutions}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:?Set WP_ADMIN_EMAIL to your security contact}"
ALLOWED_SSH_CIDR="${ALLOWED_SSH_CIDR:-0.0.0.0/0}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
REPO_URL="${REPO_URL:-https://github.com/brandonharold/repo2.git}"
REPO_BRANCH="${REPO_BRANCH:-claude/wordpress-honeypot-ubuntu-bs6ao2}"
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-$HOME/.ssh/id_ed25519.pub}"

: "${LINODE_TOKEN:?Set LINODE_TOKEN to a Linode API token}"

for dep in linode-cli jq curl; do
  command -v "$dep" >/dev/null || { echo "Missing dependency: $dep" >&2; exit 1; }
done

if [[ "$ALLOWED_SSH_CIDR" == "0.0.0.0/0" ]]; then
  echo "WARNING: ALLOWED_SSH_CIDR is 0.0.0.0/0 — SSH will be reachable from the"
  echo "         entire internet. Narrow it to your admin network or VPN."
  read -r -p "Continue anyway? [y/N] " reply
  [[ "$reply" == [yY] ]] || exit 1
fi

if [[ ! -f "$SSH_PUBKEY_PATH" ]]; then
  echo "No SSH public key at ${SSH_PUBKEY_PATH}. Set SSH_PUBKEY_PATH." >&2
  exit 1
fi
SSH_PUBKEY="$(cat "$SSH_PUBKEY_PATH")"

api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-fsS -X "$method"
    -H "Authorization: Bearer ${LINODE_TOKEN}"
    -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}" "https://api.linode.com/v4${path}"
}

# --- 1. StackScript ---
echo "==> Creating StackScript"
STACKSCRIPT_ID="$(
  linode-cli stackscripts create \
    --label "${LABEL}-provision" \
    --description "Provisions a monitored WordPress research honeypot" \
    --images "linode/ubuntu24.04" \
    --images "linode/ubuntu22.04" \
    --is_public false \
    --script "$(cat "${HERE}/stackscript.sh")" \
    --json --suppress-warnings | jq -r '.[0].id'
)"
echo "    StackScript ID: ${STACKSCRIPT_ID}"

# --- 2. Linode instance ---
echo "==> Creating Linode"
ROOT_PASS="$(openssl rand -base64 32)"

STACKSCRIPT_DATA="$(jq -nc \
  --arg domain "$DOMAIN" \
  --arg title "$SITE_TITLE" \
  --arg email "$WP_ADMIN_EMAIL" \
  --arg cidr "$ALLOWED_SSH_CIDR" \
  --arg hook "$ALERT_WEBHOOK_URL" \
  --arg repo "$REPO_URL" \
  --arg branch "$REPO_BRANCH" \
  '{HP_DOMAIN:$domain, HP_SITE_TITLE:$title, HP_ADMIN_EMAIL:$email,
    HP_ALLOWED_SSH_CIDR:$cidr, HP_ALERT_WEBHOOK_URL:$hook,
    HP_REPO_URL:$repo, HP_REPO_BRANCH:$branch}')"

LINODE_JSON="$(
  linode-cli linodes create \
    --label "$LABEL" \
    --region "$REGION" \
    --type "$TYPE" \
    --image "$IMAGE" \
    --root_pass "$ROOT_PASS" \
    --authorized_keys "$SSH_PUBKEY" \
    --stackscript_id "$STACKSCRIPT_ID" \
    --stackscript_data "$STACKSCRIPT_DATA" \
    --private_ip false \
    --backups_enabled true \
    --tags honeypot \
    --json --suppress-warnings
)"

LINODE_ID="$(echo "$LINODE_JSON" | jq -r '.[0].id')"
LINODE_IP="$(echo "$LINODE_JSON" | jq -r '.[0].ipv4[0]')"
echo "    Linode ID: ${LINODE_ID}  IP: ${LINODE_IP}"

# --- 3. Cloud Firewall ---
# A second, network-level control in front of the VM. The in-VM UFW rules can
# be disabled by anyone who achieves root on the honeypot; this cannot. The
# outbound DROP policy is what keeps a compromised honeypot from being used to
# attack third parties. Linode firewalls are stateful, so replies to allowed
# inbound web requests do not need a matching outbound rule.
echo "==> Creating and attaching Cloud Firewall"
FW_BODY="$(
  jq -c \
    --arg cidr "$ALLOWED_SSH_CIDR" \
    --arg label "${LABEL}-fw" \
    --argjson linode_id "$LINODE_ID" \
    '.label = $label
     | .devices = {linodes: [$linode_id]}
     | .rules.inbound |= map(
         if .label == "allow-ssh-admin"
         then .addresses.ipv4 = [$cidr]
         else . end)' \
    "${HERE}/cloud-firewall.json"
)"

FW_ID="$(api POST /networking/firewalls "$FW_BODY" | jq -r '.id')"
echo "    Firewall ID: ${FW_ID}"

# --- 4. Reverse DNS (best effort; requires the A record to already exist) ---
echo "==> Attempting rDNS for ${LINODE_IP} -> ${DOMAIN}"
if api PUT "/networking/ips/${LINODE_IP}" "$(jq -nc --arg d "$DOMAIN" '{rdns:$d}')" >/dev/null 2>&1; then
  echo "    rDNS set."
else
  echo "    rDNS not set — point ${DOMAIN} at ${LINODE_IP} first, then re-run:"
  echo "    linode-cli networking ip-update ${LINODE_IP} --rdns ${DOMAIN}"
fi

cat <<EOF

==> Provisioning requested.

    Linode:    ${LABEL} (id ${LINODE_ID})
    IP:        ${LINODE_IP}
    Firewall:  ${LABEL}-fw (id ${FW_ID})
    Root pass: ${ROOT_PASS}
               (store this in your password manager now — it is not saved anywhere)

    The StackScript runs on first boot and takes roughly 5-10 minutes. Watch it:

      ssh root@${LINODE_IP} 'tail -f /var/log/wp-honeypot-stackscript.log'

    When it finishes:
      1. Point ${DOMAIN} at ${LINODE_IP} (Linode DNS Manager or your registrar).
      2. Copy /root/wp-honeypot-secrets.txt off the box, then delete it.
      3. Take a clean baseline snapshot:  ./snapshot.sh ${LINODE_ID} clean-baseline
      4. Verify the site looks like an ordinary business site in a browser.

    If you lock yourself out via ALLOWED_SSH_CIDR, use the LISH console in
    Cloud Manager (Linode → Launch LISH Console) — it is out-of-band and is
    not affected by UFW or the Cloud Firewall.
EOF
