#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${HONEYPOT_LOG_DIR:-/var/log/wp-honeypot}"
WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"

send_alert() {
  local msg="$1"
  echo "[wp-honeypot-alert] ${msg}"
  if [[ -n "$WEBHOOK_URL" ]]; then
    local payload
    payload="$(jq -nc --arg text "$msg" '{text: $text}')"
    curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
      -d "$payload" "$WEBHOOK_URL" >/dev/null \
      || echo "[wp-honeypot-alert] webhook delivery failed" >&2
  fi
}

watch_honeytokens() {
  tail -n0 -F "${LOG_DIR}/honeytoken.log" 2>/dev/null | while IFS= read -r line; do
    send_alert "HONEYTOKEN ACCESSED: ${line}"
  done
}

watch_events() {
  tail -n0 -F "${LOG_DIR}/events.log" 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" == *'"type":"login_success"'* ]] || [[ "$line" == *'"severity":"critical"'* ]]; then
      send_alert "CRITICAL EVENT: ${line}"
    fi
  done
}

watch_honeytokens &
watch_events &
wait
