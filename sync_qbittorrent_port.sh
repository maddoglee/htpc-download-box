
#!/usr/bin/env bash
# Minimal sync: Gluetun /v1/portforward -> qBittorrent listen_port
# Executes the exact working one-liners Lee verified (same host, headers, cookie).
set -Eeuo pipefail

# --- Config: use ONE base URL consistently ---
QBIT_BASE="http://127.0.0.1:8080"              # keep this as 127.0.0.1 (matches your working tests)
QBIT_USER="${QBIT_USER:-admin}"
QBIT_PASS="${QBIT_PASS:-adminadmin}"
COOKIE_FILE="${COOKIE_FILE:-/tmp/qbit_cookie.txt}"
GLUETUN_PORT_URL="${GLUETUN_PORT_URL:-http://127.0.0.1:8000/v1/portforward}"

# qBittorrent WebUI has CSRF enabled by default; these headers satisfy it.
HDR_ORIGIN="Origin: ${QBIT_BASE}"
HDR_REFERER="Referer: ${QBIT_BASE}/"

# curl defaults
CURL="curl -sS --fail --location --max-time 8"

log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }

# --- 1) Login (stores cookie), EXACTLY your one-liner ---
login_resp=$($CURL --cookie-jar "$COOKIE_FILE" \
  -H "$HDR_ORIGIN" -H "$HDR_REFERER" \
  --data-urlencode "username=${QBIT_USER}" \
  --data-urlencode "password=${QBIT_PASS}" \
  "${QBIT_BASE}/api/v2/auth/login" 2>&1 || true)

if ! grep -q "Ok\." <<<"$login_resp"; then
  log "ERROR: qBittorrent login failed (response head: ${login_resp:0:120})"
  exit 1
fi

# --- 2) Read qBittorrent preferences (extract listen_port), EXACTLY your one-liner ---
prefs_resp=$($CURL --cookie "$COOKIE_FILE" \
  -H "$HDR_ORIGIN" -H "$HDR_REFERER" \
  "${QBIT_BASE}/api/v2/app/preferences" 2>&1 || true)

# If HTML, cookie wasn't accepted (host mismatch, headers missing, etc.)
if [[ -z "$prefs_resp" ]]; then
  log "ERROR: Preferences response empty from ${QBIT_BASE}/api/v2/app/preferences"
  exit 1
fi
if [[ "$prefs_resp" =~ "<!DOCTYPE html" ]]; then
  log "ERROR: Preferences returned HTML (login page). Cookie likely not sent. Ensure script uses ${QBIT_BASE} everywhere."
  exit 1
fi

qbit_port=$(printf '%s' "$prefs_resp" | jq -r '.listen_port // empty' 2>/dev/null || true)
if [[ -z "$qbit_port" || ! "$qbit_port" =~ ^[0-9]+$ ]]; then
  log "ERROR: Could not parse listen_port from preferences JSON."
  exit 1
fi

# --- 3) Read Gluetun forwarded port ---
gl_body=$($CURL "$GLUETUN_PORT_URL" 2>&1 || true)
gluetun_port=$(printf '%s' "$gl_body" | jq -r '.port // empty' 2>/dev/null || true)
if [[ -z "$gluetun_port" || ! "$gluetun_port" =~ ^[0-9]+$ ]]; then
  log "ERROR: Could not read forwarded port from Gluetun at ${GLUETUN_PORT_URL} (body head: $(printf '%s' "$gl_body" | head -c 120))"
  exit 1
fi

# --- 4) Update qBittorrent if mismatch ---
if [[ "$gluetun_port" != "$qbit_port" ]]; then
  log "Port mismatch: Gluetun=${gluetun_port}, qBittorrent=${qbit_port} -> updating qBittorrent"
  # setPreferences expects field 'json' with JSON string
  set_resp=$($CURL --cookie "$COOKIE_FILE" \
    -H "$HDR_ORIGIN" -H "$HDR_REFERER" \
    --data-urlencode "json={\"listen_port\":${gluetun_port}}" \
    "${QBIT_BASE}/api/v2/app/setPreferences" 2>&1 || true)
  # If CSRF/cookie failed here you'd see 403/HTML; your previous logs show update works.
  log "Updated qBittorrent listen port to ${gluetun_port}"
else
  log "Ports match: ${gluetun_port}"
fi
