#!/bin/sh
set -e

CONFIG_FILE="/data/config.yaml"
REGISTRATION_FILE="/data/registration.yaml"
TEMPLATE_DIR="/config-template"
SYNAPSE_APPSERVICES_DIR="/synapse-appservices"

# Ensure tokens are set (reuse from existing config if present, else generate). Multiple fallbacks for robustness.
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
if [ -z "$WHATSAPP_AS_TOKEN" ] || [ -z "$WHATSAPP_HS_TOKEN" ]; then
    if [ -f "$CONFIG_FILE" ] && grep -qE 'as_token:\s*[A-Za-z0-9_-]{20,}' "$CONFIG_FILE" 2>/dev/null; then
        echo "Reusing tokens from existing config..."
        WHATSAPP_AS_TOKEN=$(grep '^  as_token:' "$CONFIG_FILE" | sed 's/.*: *//' | tr -d ' "\047')
        WHATSAPP_HS_TOKEN=$(grep '^  hs_token:' "$CONFIG_FILE" | sed 's/.*: *//' | tr -d ' "\047')
        export WHATSAPP_AS_TOKEN WHATSAPP_HS_TOKEN
    else
        echo "WHATSAPP_AS_TOKEN and/or WHATSAPP_HS_TOKEN not set. Generating..."
        WHATSAPP_AS_TOKEN="${WHATSAPP_AS_TOKEN:-$(gen_token)}"
        WHATSAPP_HS_TOKEN="${WHATSAPP_HS_TOKEN:-$(gen_token)}"
        if [ -z "$WHATSAPP_AS_TOKEN" ] || [ -z "$WHATSAPP_HS_TOKEN" ]; then
            echo "FATAL: Could not generate tokens. Install openssl or ensure /dev/urandom is available."
            exit 1
        fi
        export WHATSAPP_AS_TOKEN WHATSAPP_HS_TOKEN
    fi
fi

# Persist pickle_key so config overwrites don't corrupt crypto DB (avoids "supplied account key is invalid")
PICKLE_KEY_FILE="/data/.pickle_key"
if [ -f "$PICKLE_KEY_FILE" ]; then
    WHATSAPP_PICKLE_KEY=$(cat "$PICKLE_KEY_FILE")
else
    WHATSAPP_PICKLE_KEY=$(gen_token)
    echo "$WHATSAPP_PICKLE_KEY" > "$PICKLE_KEY_FILE"
    chmod 600 "$PICKLE_KEY_FILE"
fi
export WHATSAPP_PICKLE_KEY

echo "Generating config from template..."
envsubst '${WHATSAPP_AS_TOKEN} ${WHATSAPP_HS_TOKEN} ${WHATSAPP_PICKLE_KEY} ${MULTICHAT_BRIDGE_STATUS_ENDPOINT} ${SYNAPSE_SERVER_NAME}' \
    < "$TEMPLATE_DIR/config.yaml" > "$CONFIG_FILE"

echo "Generating registration from template..."
envsubst '${WHATSAPP_AS_TOKEN} ${WHATSAPP_HS_TOKEN} ${SYNAPSE_SERVER_NAME}' \
    < "$TEMPLATE_DIR/registration.yaml" > "$REGISTRATION_FILE"

chown 1337:1337 "$CONFIG_FILE" "$REGISTRATION_FILE" "$PICKLE_KEY_FILE" 2>/dev/null || true
chmod 600 "$CONFIG_FILE" "$REGISTRATION_FILE"

if [ -d "$SYNAPSE_APPSERVICES_DIR" ]; then
    NEED_SYNAPSE_RESTART=false
    TARGET_REGISTRATION="$SYNAPSE_APPSERVICES_DIR/whatsapp.yaml"
    # Keep Synapse registration exactly in sync with the bridge registration.
    # Partial token matching can keep stale files around and cause 401 as_token failures.
    if [ ! -f "$TARGET_REGISTRATION" ] || ! cmp -s "$REGISTRATION_FILE" "$TARGET_REGISTRATION"; then
        echo "Syncing registration to Synapse appservices..."
        cp "$REGISTRATION_FILE" "$TARGET_REGISTRATION"
        chown 991:991 "$TARGET_REGISTRATION" 2>/dev/null || true
        chmod 644 "$TARGET_REGISTRATION" 2>/dev/null || true
        NEED_SYNAPSE_RESTART=true
    fi
    if [ "$NEED_SYNAPSE_RESTART" = true ]; then
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
fi

echo "Starting mautrix-whatsapp bridge..."
exec /custom-docker-run.sh "$@"
