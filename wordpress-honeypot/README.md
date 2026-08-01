# WordPress Honeypot for Ubuntu Server

A deployable, monitored WordPress site used as a **research honeypot** — a
generic-looking small-business site whose real purpose is to capture recon,
brute-force, and exploitation *attempts* against WordPress, without exposing
real attack surface an intruder could actually use.

## Before you deploy — read this

- **Only deploy this on infrastructure you own or are explicitly authorized to
  operate as a honeypot.** Unauthorized deployment, or deployment that could
  mislead third parties into thinking they're interacting with a real
  business, may carry legal risk depending on your jurisdiction.
- **Isolate it.** Put the VM in its own network segment/VPC with no route to
  anything sensitive. If it is ever fully compromised despite the hardening
  below, it should not be able to reach other systems.
- **Handle captured data responsibly.** The logger records source IPs, user
  agents, and *usernames* attackers try — it deliberately does **not** record
  passwords, to avoid harvesting/storing third-party credential material.
  Treat captured IPs as personal data under your local law (e.g. GDPR) and
  retain/share accordingly.
- **Don't attack back.** Nothing here fires exploits, scans, or retaliates
  against source IPs. It only observes and logs.
- This is a *logging and observation* honeypot, not an intentionally
  vulnerable target. Defaults disable plugin/theme installation and file
  editing from the web UI, and block dangerous XML-RPC methods, so a leaked
  admin password can't be turned into remote code execution. See "Increasing
  fidelity" below if your research requires letting attackers go further —
  doing so meaningfully raises risk and should only be done in a fully
  isolated, disposable lab.

## What gets deployed

- **LEMP stack**: Nginx + PHP-FPM + MariaDB, installed fresh via `apt`.
- **WordPress core** (latest, via WP-CLI) with generic small-business content
  (Home/About/Services/Blog/Contact + a few filler posts) — nothing
  identifies it as a honeypot to a visitor or casual scanner.
- **Randomly generated** DB and WP-admin credentials, written once to
  `/root/wp-honeypot-secrets.txt` (root-only). Nobody is meant to log into
  wp-admin over the web — manage the install via WP-CLI/SSH instead. Any
  successful web login is therefore itself a signal worth alerting on.
- **A logging mu-plugin** (`mu-plugins/honeypot-logger.php`) that records
  failed/successful logins, XML-RPC calls, sensitive REST API probing, and
  recon-flavored 404s (`.env`, `wp-config.php.bak`, `phpmyadmin`, etc.) as
  JSON lines.
- **Honeytoken files** (`wp-config.php.bak`, `.env`, `.git/config`,
  `backup.zip`) — inert, non-functional decoys. No legitimate visitor ever
  requests them, so *any* hit is a high-confidence alert.
- **fail2ban** tuned for research: a generous threshold on login brute force
  (so you still capture a useful sample before banning) and an instant ban on
  any honeytoken access.
- **Egress-restricted UFW**: inbound 22/80/443 only; outbound limited to
  DNS/NTP/HTTPS (updates + webhook alerts) — this is the main safety net if
  the box is ever compromised.
- **unattended-upgrades** for OS-level patching (the WordPress layer is the
  intended attack surface; the underlying OS shouldn't be).
- **A log-tailing alert service** (systemd unit) that fires a webhook (e.g.
  Slack/Discord/generic HTTP) on honeytoken access or a successful admin
  login.

## Requirements

- A fresh Ubuntu 22.04 or 24.04 LTS server (VM recommended), isolated network
  segment, root/sudo access.
- A domain or subdomain pointed at the host (or just use the server IP for
  testing).

## Deploying on Linode / Akamai

If you're hosting this on a Linode VM, use **[`linode/`](linode/)** instead of
running `install.sh` by hand. It adds a StackScript that performs this entire
build on first boot, an egress-restricted Cloud Firewall enforced outside the
VM (the control that still holds if the honeypot is fully compromised),
snapshot/reset tooling, and notes on the Akamai AUP as it applies to running a
honeypot on your own account.

```bash
cd linode
export LINODE_TOKEN=... DOMAIN=... WP_ADMIN_EMAIL=... ALLOWED_SSH_CIDR=...
./provision-linode.sh
```

The manual path below still applies to any other Ubuntu host.

## Quick start (any Ubuntu host)

```bash
git clone <this repo> && cd wordpress-honeypot
cp .env.example .env
$EDITOR .env                     # set DOMAIN, WP_ADMIN_EMAIL, SITE_TITLE, ALERT_WEBHOOK_URL
sudo ./install.sh
```

`install.sh` runs, in order:

| Script | Purpose |
|---|---|
| `scripts/01-provision-os.sh` | OS updates, UFW (egress-restricted), unattended-upgrades, base tooling |
| `scripts/02-install-lemp.sh` | Nginx, MariaDB, PHP-FPM |
| `scripts/03-install-wordpress.sh` | DB + WP-CLI + WordPress core, random credentials |
| `scripts/04-populate-content.sh` | Generic pages/posts, nav menu, default theme |
| `scripts/05-harden-and-monitor.sh` | mu-plugin logger, nginx logging/rate-limits, fail2ban, alert service |
| `scripts/06-deploy-honeytokens.sh` | Decoy files + honeytoken logging |

Credentials are printed to `/root/wp-honeypot-secrets.txt` (mode `600`) at
the end of the run — copy them out and delete the file if you don't need
root on the box to see them.

### Re-running a single step

`install.sh` is not resumable as a whole — re-running it would try to
reinstall WordPress core over an existing install. If one step fails, fix it
and run that step and the ones after it directly:

```bash
cd wordpress-honeypot
set -a; source .env; set +a
export WP_ROOT="/var/www/${DOMAIN}" HONEYPOT_SRC="$PWD"

bash scripts/04-populate-content.sh      # then 05, 06
bash scripts/05-harden-and-monitor.sh
bash scripts/06-deploy-honeytokens.sh
```

Step 04 deletes all existing posts and pages before creating its own, so
re-running it is safe and won't duplicate content.

## Reviewing captured activity

```bash
tail -f /var/log/wp-honeypot/events.log       # login attempts, xmlrpc, recon 404s, REST probing
tail -f /var/log/wp-honeypot/honeytoken.log   # decoy-file hits (near-zero false positive rate)
tail -f /var/log/nginx/wp-honeypot-access.log # full raw access log
```

Each `events.log` line is a JSON object, e.g.:

```json
{"ts":"2026-08-01T14:02:11+00:00","type":"login_failed","ip":"203.0.113.9","ua":"...","username":"admin"}
```

## Alerting

`monitoring/alert-watch.sh` runs as the `wp-honeypot-alert` systemd service
and posts to `ALERT_WEBHOOK_URL` (from `/etc/wp-honeypot/alert.env`) whenever:

- a honeytoken file is requested, or
- a web login to wp-admin actually succeeds (it shouldn't — admin the site
  via WP-CLI, not the browser).

```bash
systemctl status wp-honeypot-alert
journalctl -u wp-honeypot-alert -f
```

## Resetting

Take a VM/disk snapshot right after `install.sh` completes and content looks
right — that's the fastest, safest way to reset after a research window or a
deeper compromise than the sandboxing was meant to allow. Don't try to
"clean" a box you suspect was fully compromised; restore from snapshot.

On Linode, `linode/snapshot.sh` and `linode/collect-logs.sh` implement this
lifecycle. Collect logs *before* restoring — a restore overwrites the disks.

## Increasing fidelity (optional, higher risk)

If your research goal is to observe *post-exploitation* behavior rather than
just recon/brute-force, you can deliberately loosen defaults — for example,
re-enable `DISALLOW_FILE_MODS` and install an older, known-vulnerable
plugin. Only do this in a fully isolated, snapshot-and-reset lab with no
egress beyond your logging collector; the egress-restricted UFW rules in
`scripts/01-provision-os.sh` are your last line of defense and should stay
in place regardless.

## File tree

```
wordpress-honeypot/
├── install.sh
├── .env.example
├── scripts/            # numbered provisioning steps, run by install.sh
├── config/             # nginx, fail2ban, logrotate, systemd unit templates
├── mu-plugins/         # honeypot-logger.php, deployed into wp-content/mu-plugins
├── monitoring/         # alert-watch.sh + its env example
└── linode/             # Linode/Akamai: StackScript, Cloud Firewall, snapshots
```
