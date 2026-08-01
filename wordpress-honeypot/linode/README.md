# Deploying the honeypot on Linode / Akamai

The stack in `../` is plain Ubuntu and runs on a Linode VM unchanged. This
directory adds the Linode-specific layer: first-boot provisioning, a
network-level firewall in front of the VM, and snapshot/collect tooling for
the research lifecycle.

| File | Purpose |
|---|---|
| `stackscript.sh` | Linode StackScript — runs the whole build on first boot |
| `cloud-firewall.json` | Egress-restricted Cloud Firewall ruleset |
| `provision-linode.sh` | One-shot: StackScript + Linode + Firewall + rDNS |
| `snapshot.sh` | Take / list / restore the clean baseline snapshot |
| `collect-logs.sh` | Pull captured logs off the box before a reset |

## Read this before you deploy

Everything in the parent README's "Before you deploy" section applies. Two
things are specific to running this on Linode/Akamai:

- **The Akamai/Linode Acceptable Use Policy governs this box.** Operating a
  honeypot on your own Linode is not itself prohibited, but you remain
  responsible for all traffic it originates. If the honeypot were compromised
  and used to scan or attack third parties, that is an AUP violation against
  *your* account, and Akamai will act on the resulting abuse reports. The
  outbound `DROP` policy on the Cloud Firewall is the control that prevents
  this — do not remove it. Read the current AUP before deploying, and if your
  research plan involves deliberately letting attackers execute code, contact
  Linode Support first rather than discovering their position via an abuse
  ticket.
- **Expect abuse tickets anyway.** A box whose entire purpose is to attract
  scanners will show up in other people's threat feeds. Keep the account's
  contact email monitored and be ready to explain the deployment.

## Two firewalls, on purpose

`scripts/01-provision-os.sh` configures UFW *inside* the VM, and
`cloud-firewall.json` configures a Cloud Firewall *in front of* it. This is
deliberate, not redundant: anyone who reaches root on the honeypot can
disable UFW, but they cannot touch the Cloud Firewall, which is enforced on
Linode's network and managed through your account. It is the control that
actually holds if the box is fully compromised.

Both default to deny-in/deny-out with the same narrow allowances (SSH from
your admin CIDR, inbound 80/443, outbound DNS/NTP/HTTP/HTTPS). Linode
firewalls are stateful, so replies to allowed inbound web requests don't need
a matching outbound rule.

## Quick start

```bash
pip install linode-cli
export LINODE_TOKEN=...                      # Linodes + StackScripts + Firewalls RW
export DOMAIN=honeypot.example.com
export WP_ADMIN_EMAIL=security-team@example.com
export ALLOWED_SSH_CIDR=198.51.100.7/32      # your admin IP — do not leave open
export ALERT_WEBHOOK_URL=https://hooks.slack.com/services/...

./provision-linode.sh
```

Defaults: `g6-nanode-1` (Nanode 1GB) in `us-east` on `linode/ubuntu24.04`,
with Backups enabled. Override with `TYPE`, `REGION`, `IMAGE`, `LABEL`. A
Nanode is ample — the site is static-ish and the load is scanners.

The StackScript takes roughly 5–10 minutes on first boot:

```bash
ssh root@<ip> 'tail -f /var/log/wp-honeypot-stackscript.log'
```

### If you'd rather use Cloud Manager

Create the StackScript by pasting `stackscript.sh` into **StackScripts →
Create** (target the Ubuntu 24.04 and 22.04 images), then deploy a Linode
from it and fill in the UDF fields the form presents. Create the firewall
separately under **Firewalls** using `cloud-firewall.json` as the reference
for the rules, and attach it to the Linode.

### Private repository note

`stackscript.sh` clones this repo over HTTPS on first boot. If the repo is
private, the clone will fail — either make it public, bake a deploy token
into `HP_REPO_URL` (it lands in the StackScript's data and on disk, so treat
it as low-value and revocable), or skip the StackScript and run
`../install.sh` manually over SSH.

## After it comes up

1. Point `DOMAIN` at the Linode's IP (Linode **DNS Manager** or your
   registrar), then set rDNS if `provision-linode.sh` couldn't:
   `linode-cli networking ip-update <ip> --rdns <domain>`.
   Matching forward/reverse DNS makes the host look like ordinary
   infrastructure rather than something freshly stood up.
2. Copy `/root/wp-honeypot-secrets.txt` off the box and delete it.
3. Load the site in a browser and confirm it reads as an ordinary business
   site — no honeypot tells, no default WordPress placeholder content.
4. Take the clean baseline: `./snapshot.sh <linode_id> clean-baseline`.

## TLS

The nginx config ships HTTP-only so the site is reachable before DNS
settles. Once `DOMAIN` resolves, add a certificate — a honeypot with no
HTTPS in 2026 looks anomalous, and browsers flag it:

```bash
ssh root@<ip>
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d honeypot.example.com --agree-tos -m security-team@example.com
```

Certbot needs outbound 443 (already allowed) and inbound 80 for the HTTP-01
challenge (already allowed). Its nginx edits preserve the honeytoken and
`wp-login.php` logging blocks, since those are `location` directives it
doesn't touch.

## Research lifecycle

```bash
./snapshot.sh <linode_id> clean-baseline      # once, after verifying the build
# ... run the research window ...
./collect-logs.sh root@<ip>                   # pull captures to your workstation
./snapshot.sh list <linode_id>                # find the baseline backup id
./snapshot.sh restore <linode_id> <backup_id> # reset to clean
```

Collect logs *before* restoring — a restore overwrites the disks and anything
you haven't copied off is gone.

## Cost

A Nanode with Backups is roughly $7/month at current list prices (Backups is
about 25% of the plan cost); check current pricing before committing. Cloud
Firewalls are free. If you tear the honeypot down between research windows,
capture an **Image** rather than paying to keep the Linode running — but note
Linode bills Linodes even while powered off, so delete rather than shut down.

## Recovering from a lockout

If `ALLOWED_SSH_CIDR` is wrong or your IP changes, use **LISH** (Cloud
Manager → your Linode → *Launch LISH Console*). It's out-of-band serial
access, unaffected by UFW and the Cloud Firewall. Fix the CIDR with
`linode-cli firewalls rules-update <fw_id> ...` or in Cloud Manager.
