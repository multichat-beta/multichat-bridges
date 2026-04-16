FROM matrixdotorg/synapse:latest

USER root
# Install gettext for envsubst (config template substitution)
RUN apt-get update && apt-get install -y --no-install-recommends gettext-base && rm -rf /var/lib/apt/lists/*

# Copy config template (generated at runtime with envsubst to inject POSTGRES_*)
COPY synapse.yaml.template /app/synapse.yaml.template
COPY log_config.yaml.template /app/log_config.yaml.template

# Copy appservice placeholders (Synapse needs valid tokens to start; bridges overwrite at runtime)
COPY appservice-placeholders/whatsapp.yaml /appservice-templates/whatsapp.yaml
COPY appservice-placeholders/telegram.yaml /appservice-templates/telegram.yaml
COPY appservice-placeholders/meta.yaml /appservice-templates/meta.yaml
COPY appservice-placeholders/gmessages.yaml /appservice-templates/gmessages.yaml

# Copy custom entrypoint
COPY docker-entrypoint.sh /custom-entrypoint.sh

USER root
RUN chmod +x /custom-entrypoint.sh

ENTRYPOINT ["/custom-entrypoint.sh"]

