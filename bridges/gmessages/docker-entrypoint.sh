#!/bin/sh
# Required environment variables:
#   GMESSAGES_POSTGRES_USER      - postgres username for this bridge
#   GMESSAGES_POSTGRES_PASSWORD  - postgres password for this bridge
#   GMESSAGES_POSTGRES_DB        - postgres database name for this bridge
#   SYNAPSE_SERVER_NAME          - your Matrix server domain (e.g. example.com)
#   GMESSAGES_AS_TOKEN           - (optional) appservice token
#   GMESSAGES_HS_TOKEN           - (optional) homeserver token
#   MULTICHAT_BRIDGE_STATUS_ENDPOINT - (optional) URL to POST bridge status updates
set -e

CONFIG_FILE="/data/config.yaml"
REGISTRATION_FILE="/data/registration.yaml"
SYNAPSE_APPSERVICES_DIR="/synapse-appservices"

PORT="${GMESSAGES_PORT:-29320}"
HS_ADDR="${GMESSAGES_HOMESERVER_ADDRESS:-http://synapse:8008}"
HS_DOMAIN="${GMESSAGES_HOMESERVER_DOMAIN:-localhost}"
AS_ADDR="${GMESSAGES_APPSERVICE_ADDRESS:-http://gmessages:${PORT}}"
DB_SSLMODE="${GMESSAGES_DB_SSLMODE:-disable}"

# Postgres vars are required (bridgev2 expects DB configured)
: "${GMESSAGES_POSTGRES_USER:?GMESSAGES_POSTGRES_USER is required}"
: "${GMESSAGES_POSTGRES_PASSWORD:?GMESSAGES_POSTGRES_PASSWORD is required}"
: "${GMESSAGES_POSTGRES_DB:?GMESSAGES_POSTGRES_DB is required}"

DB_URI="postgres://${GMESSAGES_POSTGRES_USER}:${GMESSAGES_POSTGRES_PASSWORD}@postgres_gmessages:5432/${GMESSAGES_POSTGRES_DB}?sslmode=${DB_SSLMODE}"

patch_config() {
  local can_patch_managed="false"
  if [ -f "/data/.multichat_managed" ] || [ "${GMESSAGES_FORCE_CONFIG_PATCH:-false}" = "true" ]; then
    can_patch_managed="true"
  fi

  # yq-go is included in upstream image
  if [ "${can_patch_managed}" = "true" ]; then
    yq -I4 e -i \
      ".homeserver.address = \"${HS_ADDR}\" | \
       .homeserver.domain = \"${HS_DOMAIN}\" | \
       .appservice.address = \"${AS_ADDR}\" | \
       .appservice.hostname = \"0.0.0.0\" | \
       .appservice.port = ${PORT} | \
       .database.type = \"postgres\" | \
       .database.uri = \"${DB_URI}\" | \
       .bridge.bridge_status_notices = \"all\" | \
       .bridge.permissions.\"*\" = \"relay\" | \
       .bridge.permissions.\"${HS_DOMAIN}\" = \"user\" | \
       .bridge.permissions.\"@admin:${HS_DOMAIN}\" = \"admin\" | \
         .encryption.allow = true | \
         .encryption.default = true | \
         .encryption.require = false | \
         .encryption.allow_key_sharing = true" \
      "${CONFIG_FILE}"
  fi

  if [ -n "${GMESSAGES_AS_TOKEN:-}" ] && [ -n "${GMESSAGES_HS_TOKEN:-}" ]; then
    yq -I4 e -i \
      ".appservice.as_token = \"${GMESSAGES_AS_TOKEN}\" | \
       .appservice.hs_token = \"${GMESSAGES_HS_TOKEN}\"" \
      "${CONFIG_FILE}"
  fi

  # Always patch the status endpoint when provided (safe, single-field change).
  if [ -n "${MULTICHAT_BRIDGE_STATUS_ENDPOINT:-}" ]; then
    yq -I4 e -i \
      ".homeserver.status_endpoint = \"${MULTICHAT_BRIDGE_STATUS_ENDPOINT}\"" \
      "${CONFIG_FILE}"
  fi
}

ensure_config_exists() {
  if [ -f "${CONFIG_FILE}" ]; then
    # Allow applying safe patches (e.g. status_endpoint) on restarts even if
    # the config file already exists.
    patch_config
    return 0
  fi

  echo "Config not found, generating default config..."
  /usr/bin/mautrix-gmessages -c "${CONFIG_FILE}" -e
  touch /data/.multichat_managed

  echo "Patching mandatory fields for Docker + this repo..."
  patch_config

  echo "Generated ${CONFIG_FILE}."
}

ensure_registration_exists() {
  if [ -f "${REGISTRATION_FILE}" ]; then
    return 0
  fi

  echo "Registration not found, generating registration..."
  /usr/bin/mautrix-gmessages -g -c "${CONFIG_FILE}" -r "${REGISTRATION_FILE}"

  # The -g command writes tokens into config.yaml; keep our mandatory fields consistent.
  patch_config

  echo "Generated ${REGISTRATION_FILE}."
}

patch_registration() {
  if [ ! -f "${REGISTRATION_FILE}" ]; then
    return 0
  fi

  # Keep registration endpoint aligned with the running service.
  # This also fixes older stale files that still contain "gmmessages".
  yq -I4 e -i \
    ".url = \"${AS_ADDR}\" | \
     .id = \"gmessages\" | \
     .sender_localpart = \"gmessagesbot\"" \
    "${REGISTRATION_FILE}" 2>/dev/null || true

  if [ -n "${GMESSAGES_AS_TOKEN:-}" ] && [ -n "${GMESSAGES_HS_TOKEN:-}" ]; then
    yq -I4 e -i \
      ".as_token = \"${GMESSAGES_AS_TOKEN}\" | \
       .hs_token = \"${GMESSAGES_HS_TOKEN}\"" \
      "${REGISTRATION_FILE}" 2>/dev/null || true
  fi

  if grep -q 'gmmessages' "${REGISTRATION_FILE}" 2>/dev/null; then
    sed -i 's/gmmessages/gmessages/g' "${REGISTRATION_FILE}" || true
  fi
}

sync_registration_to_synapse() {
  if [ ! -d "${SYNAPSE_APPSERVICES_DIR}" ]; then
    return 0
  fi

  local dst="${SYNAPSE_APPSERVICES_DIR}/gmessages.yaml"
  if [ -f "${dst}" ] && command -v cmp >/dev/null 2>&1 && cmp -s "${REGISTRATION_FILE}" "${dst}"; then
    echo "Synapse registration already up to date."
    return 0
  fi

  echo "Syncing registration to Synapse appservices..."
  cp "${REGISTRATION_FILE}" "${dst}"
  chown 991:991 "${dst}" 2>/dev/null || true
  chmod 644 "${dst}" 2>/dev/null || true

  # Restart Synapse if docker is available (mirrors whatsapp/telegram pattern)
  if command -v docker >/dev/null 2>&1; then
    for name in mc_local-synapse-1 mc_develop-synapse-1 mc_staging-synapse-1 mc_prod-synapse-1 synapse synapse-synapse-1 synapse-1; do
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        echo "Restarting Synapse to pick up gm messages registration..."
        docker restart "${name}" 2>/dev/null && break
      fi
    done
  fi
}

ensure_config_exists
ensure_registration_exists
patch_registration
sync_registration_to_synapse

# Fix permissions (upstream expects /data owned by UID/GID; their default is 1337)
chown -R 1337:1337 /data 2>/dev/null || true

echo "Starting mautrix-gmessages bridge..."
cd /data
exec su-exec 1337:1337 /usr/bin/mautrix-gmessages -c "${CONFIG_FILE}"
