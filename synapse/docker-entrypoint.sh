#!/bin/bash
set -e

# Synapse runs as UID 991:991
SYNAPSE_UID=991
SYNAPSE_GID=991

echo "Initializing Synapse data directories..."

# Create required directories if they don't exist
mkdir -p /data/media_store
mkdir -p /data/uploads
mkdir -p /data/appservices

render_appservice() {
    local name="$1"
    local src="/appservice-templates/${name}.yaml"
    local dst="/data/appservices/${name}.yaml"

    if [ ! -f "$src" ]; then
        return
    fi

    case "$name" in
        whatsapp)
            if [ -n "${WHATSAPP_AS_TOKEN:-}" ] && [ -n "${WHATSAPP_HS_TOKEN:-}" ]; then
                envsubst '${WHATSAPP_AS_TOKEN} ${WHATSAPP_HS_TOKEN} ${SYNAPSE_SERVER_NAME}' < "$src" > "$dst"
                chown $SYNAPSE_UID:$SYNAPSE_GID "$dst"
                return
            fi
            ;;
        telegram)
            if [ -n "${TELEGRAM_AS_TOKEN:-}" ] && [ -n "${TELEGRAM_HS_TOKEN:-}" ]; then
                envsubst '${TELEGRAM_AS_TOKEN} ${TELEGRAM_HS_TOKEN} ${SYNAPSE_SERVER_NAME}' < "$src" > "$dst"
                chown $SYNAPSE_UID:$SYNAPSE_GID "$dst"
                return
            fi
            ;;
        meta)
            if [ -n "${META_AS_TOKEN:-}" ] && [ -n "${META_HS_TOKEN:-}" ]; then
                envsubst '${META_AS_TOKEN} ${META_HS_TOKEN} ${SYNAPSE_SERVER_NAME}' < "$src" > "$dst"
                chown $SYNAPSE_UID:$SYNAPSE_GID "$dst"
                return
            fi
            ;;
        gmessages)
            if [ -n "${GMESSAGES_AS_TOKEN:-}" ] && [ -n "${GMESSAGES_HS_TOKEN:-}" ]; then
                envsubst '${GMESSAGES_AS_TOKEN} ${GMESSAGES_HS_TOKEN} ${SYNAPSE_SERVER_NAME}' < "$src" > "$dst"
                chown $SYNAPSE_UID:$SYNAPSE_GID "$dst"
                return
            fi
            ;;
    esac

    cp "$src" "$dst"
    chown $SYNAPSE_UID:$SYNAPSE_GID "$dst"
}

# Fix ownership of the data directory
chown -R $SYNAPSE_UID:$SYNAPSE_GID /data

# Render appservice registrations before Synapse boots so fresh runtime volumes
# already match runtime.env tokens after `down --volumes` resets.
render_appservice whatsapp
render_appservice telegram
render_appservice meta
render_appservice gmessages

# Generate synapse.yaml from template with env vars (keeps secrets out of git)
echo "Generating synapse config from template..."
envsubst '${POSTGRES_USER} ${POSTGRES_PASSWORD} ${POSTGRES_DB} ${POSTGRES_HOST} ${SYNAPSE_SERVER_NAME}' < /app/synapse.yaml.template > /data/config/synapse.yaml
chown $SYNAPSE_UID:$SYNAPSE_GID /data/config/synapse.yaml

# Copy log config (includes DEBUG for synapse.http/sync for troubleshooting)
cp /app/log_config.yaml.template /data/config/log_config.yaml
chown $SYNAPSE_UID:$SYNAPSE_GID /data/config/log_config.yaml

echo "Starting Synapse..."

# Run the original entrypoint
exec /start.py "$@"