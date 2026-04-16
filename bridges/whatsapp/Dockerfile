FROM dock.mau.dev/mautrix/whatsapp:latest

USER root
# Install gettext for envsubst, openssl for token generation, curl for health checks
RUN apk add --no-cache gettext openssl curl docker-cli 2>/dev/null || \
    (apt-get update && apt-get install -y --no-install-recommends gettext-base openssl ca-certificates curl docker.io && rm -rf /var/lib/apt/lists/*)

# Copy config and registration templates (secrets injected at runtime)
COPY config.yaml.template /config-template/config.yaml
COPY registration.yaml.template /config-template/registration.yaml

# Copy custom entrypoint and docker-run wrapper
COPY docker-entrypoint.sh /custom-entrypoint.sh
COPY custom-docker-run.sh /custom-docker-run.sh
RUN chmod +x /custom-entrypoint.sh /custom-docker-run.sh

ENTRYPOINT ["/custom-entrypoint.sh"]
