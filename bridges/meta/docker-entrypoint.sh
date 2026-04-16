#!/bin/sh
set -e

CONFIG_FILE="/data/config.yaml"
REGISTRATION_FILE="/data/registration.yaml"
TEMPLATE_DIR="/config-template"
SYNAPSE_APPSERVICES_DIR="/synapse-appservices"

# Ensure tokens are set (generate if not). Use multiple fallbacks; mautrix base may lack openssl.
gen_token() {
  t=""
  if command -v openssl >/dev/null 2>&1; then
    t=$(openssl rand -base64 43 2>/dev/null | tr -d '\n/+=' | head -c 64)
  fi
  if [ -z "$t" ] && command -v python3 >/dev/null 2>&1; then
    t=$(python3 -c 'import secrets; print(secrets.token_urlsafe(43))' 2>/dev/null | tr -d '\n' | head -c 64)
  fi
  if [ -z "$t" ]; then
    t=$(head -c 48 /dev/urandom 2>/dev/null | base64 2>/dev/null | tr -d '\n/+=' | head -c 64)
  fi
  echo "$t"
}
if [ -z "$META_AS_TOKEN" ] || [ -z "$META_HS_TOKEN" ]; then
    # Reuse tokens from previous runs if they exist in the persisted volume.
    if [ -f "$REGISTRATION_FILE" ] && grep -q '^as_token:' "$REGISTRATION_FILE" 2>/dev/null; then
        echo "Reusing tokens from existing registration..."
        META_AS_TOKEN=$(grep '^as_token:' "$REGISTRATION_FILE" | sed 's/as_token: *["\x27]*\(.*\)["\x27]*/\1/' | head -1)
        META_HS_TOKEN=$(grep '^hs_token:' "$REGISTRATION_FILE" | sed 's/hs_token: *["\x27]*\(.*\)["\x27]*/\1/' | head -1)
        export META_AS_TOKEN META_HS_TOKEN
    elif [ -f "$CONFIG_FILE" ] && grep -q '^\s*as_token:' "$CONFIG_FILE" 2>/dev/null; then
        echo "Reusing tokens from existing config..."
        META_AS_TOKEN=$(grep '^\s*as_token:' "$CONFIG_FILE" | sed 's/.*: *//' | tr -d ' "\x27' | head -1)
        META_HS_TOKEN=$(grep '^\s*hs_token:' "$CONFIG_FILE" | sed 's/.*: *//' | tr -d ' "\x27' | head -1)
        export META_AS_TOKEN META_HS_TOKEN
    else
        echo "META_AS_TOKEN and/or META_HS_TOKEN not set. Generating..."
        META_AS_TOKEN="${META_AS_TOKEN:-$(gen_token)}"
        META_HS_TOKEN="${META_HS_TOKEN:-$(gen_token)}"
        if [ -z "$META_AS_TOKEN" ] || [ -z "$META_HS_TOKEN" ]; then
            echo "FATAL: Could not generate tokens. Install openssl or ensure /dev/urandom is available."
            exit 1
        fi
        export META_AS_TOKEN META_HS_TOKEN
    fi
fi

# Persist pickle_key so config overwrites don't corrupt crypto DB (avoids "supplied account key is invalid")
PICKLE_KEY_FILE="/data/.pickle_key"
if [ -f "$PICKLE_KEY_FILE" ]; then
    META_PICKLE_KEY=$(cat "$PICKLE_KEY_FILE")
else
    META_PICKLE_KEY=$(gen_token)
    echo "$META_PICKLE_KEY" > "$PICKLE_KEY_FILE"
    chmod 600 "$PICKLE_KEY_FILE"
fi
export META_PICKLE_KEY

echo "Generating config from template..."
envsubst '${META_AS_TOKEN} ${META_HS_TOKEN} ${META_PICKLE_KEY} ${META_POSTGRES_USER} ${META_POSTGRES_PASSWORD} ${META_POSTGRES_DB} ${MULTICHAT_BRIDGE_STATUS_ENDPOINT} ${SYNAPSE_SERVER_NAME}' \
    < "$TEMPLATE_DIR/config.yaml" > "$CONFIG_FILE"

echo "Generating registration from template..."
envsubst '${META_AS_TOKEN} ${META_HS_TOKEN} ${SYNAPSE_SERVER_NAME}' \
    < "$TEMPLATE_DIR/registration.yaml" > "$REGISTRATION_FILE"

chown 1337:1337 "$CONFIG_FILE" "$REGISTRATION_FILE" "$PICKLE_KEY_FILE" 2>/dev/null || true
chmod 600 "$CONFIG_FILE" "$REGISTRATION_FILE"

if [ -d "$SYNAPSE_APPSERVICES_DIR" ]; then
    echo "Syncing registration to Synapse appservices..."
    cp "$REGISTRATION_FILE" "$SYNAPSE_APPSERVICES_DIR/meta.yaml"
    # Restart Synapse to pick up registration, then wait for it to be ready
    for name in mc_local-synapse-1 mc_develop-synapse-1 mc_staging-synapse-1 mc_prod-synapse-1 synapse-synapse-1 synapse synapse-1; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
            echo "Restarting Synapse to pick up registration..."
            docker restart "$name" 2>/dev/null && break
        fi
    done
    echo "Waiting for Synapse to be ready..."
    for i in $(seq 1 30); do
        sleep 2
        if wget -q -O /dev/null --timeout=2 http://synapse:8008/health 2>/dev/null || curl -sf --max-time 2 http://synapse:8008/health >/dev/null 2>&1; then
            echo "Synapse is ready."
            break
        fi
        echo "  Waiting... ($i/30)"
    done
fi

echo "Starting mautrix-meta..."
exec /usr/bin/mautrix-meta -c "$CONFIG_FILE"
