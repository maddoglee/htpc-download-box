#!/usr/bin/env bash
# Minimal sync: Gluetun /v1/portforward -> qBittorrent listen_port
set -Eeuo pipefail

# --- Config ---
QBIT_BASE="http://127.0.0.1:8080"
QBIT_USER="${QBIT_USER:-admin}"
QBIT_PASS="${QBIT_PASS:-adminadmin}"
COOKIE_FILE="${COOKIE_FILE:-/tmp/qbit_cookie.txt}"
GLUETUN_PORT_URL="${GLUETUN_PORT_URL:-http://127.0.0.1:8000/v1/portforward}"

HDR_ORIGIN="Origin: ${QBIT_BASE}"
HDR_REFERER="Referer: ${QBIT_BASE}/"

CURL="curl -sS --location --max-time 8"

log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }

# --- 1) Login ---
http_code=$($CURL --cookie-jar "$COOKIE_FILE" \
  -H "$HDR_ORIGIN" -H "$HDR_REFERER" \
  --data-urlencode "username=${QBIT_USER}" \
  --data-urlencode "password=${QBIT_PASS}" \
  -o /dev/null -w "%{http_code}" \
  "${QBIT_BASE}/api/v2/auth/login" 2>/dev/null || echo "000")

if [[ "$http_code" != "200" && "$http_code" != "204" ]]; then
  log "ERROR: qBittorrent login failed with HTTP status: ${http_code}"
  exit 1
fi

# --- 2) Read qBittorrent preferences ---
prefs_resp=$($CURL --cookie "$COOKIE_FILE" \
  -H "$HDR_ORIGIN" -H "$HDR_REFERER" \
  "${QBIT_BASE}/api/v2/app/preferences" 2>/dev/null || true)

if [[ -z "$prefs_resp" ]]; then
  log "ERROR: Preferences response empty from ${QBIT_BASE}/api/v2/app/preferences"
  exit 1
fi
if [[ "$prefs_resp" =~ "<!DOCTYPE html" ]]; then
  log "ERROR: Preferences returned HTML (login page). Cookie not valid."
  exit 1
fi

qbit_port=$(printf '%s' "$prefs_resp" | jq -r '.listen_port // empty' 2>/dev/null || true)
if [[ -z "$qbit_port" || ! "$qbit_port" =~ ^[0-9]+$ ]]; then
  log "ERROR: Could not parse listen_port from preferences JSON."
  exit 1
fi

# --- 3) Read Gluetun forwarded port ---
gl_body=$($CURL "$GLUETUN_PORT_URL" 2>/dev/null || true)
gluetun_port=$(printf '%s' "$gl_body" | jq -r '.port // empty' 2>/dev/null || true)
if [[ -z "$gluetun_port" || ! "$gluetun_port" =~ ^[0-9]+$ ]]; then
  log "ERROR: Could not read forwarded port from Gluetun at ${GLUETUN_PORT_URL}"
  exit 1
fi

# --- 4) Update qBittorrent if mismatch ---
if [[ "$gluetun_port" != "$qbit_port" ]]; then
  log "Port mismatch: Gluetun=${gluetun_port}, qBittorrent=${qbit_port} -> updating qBittorrent"
  
  set_code=$($CURL --cookie "$COOKIE_FILE" \
    -H "$HDR_ORIGIN" -H "$HDR_REFERER" \
    --data-urlencode "json={\"listen_port\":${gluetun_port}}" \
    -o /dev/null -w "%{http_code}" \
    "${QBIT_BASE}/api/v2/app/setPreferences" 2>/dev/null || echo "000")

  if [[ "$set_code" == "200" || "$set_code" == "204" ]]; then
    log "Updated qBittorrent listen port to ${gluetun_port}"
  else
    log "ERROR: Failed to update preferences (HTTP ${set_code})"
    exit 1
  fi
fi
