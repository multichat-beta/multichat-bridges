FROM dock.mau.dev/mautrix/telegram:v0.15.2

USER root
# Install docker CLI and gettext for envsubst
RUN apk add --no-cache docker-cli curl wget gettext || \
    (apt-get update && apt-get install -y docker.io curl wget gettext-base && rm -rf /var/lib/apt/lists/*) || \
    echo "Could not install docker CLI - automatic synapse restart will be disabled"

# Copy config and registration templates (secrets injected at runtime)
COPY config.yaml.template /config-template/config.yaml
COPY registration.yaml.template /config-template/registration.yaml

# Copy custom entrypoint script
COPY docker-entrypoint.sh /custom-entrypoint.sh
RUN chmod +x /custom-entrypoint.sh

ENTRYPOINT ["/custom-entrypoint.sh"]

