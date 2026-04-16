FROM dock.mau.dev/mautrix/gmessages:v0.2601.0

USER root
# Install docker CLI for optional Synapse restart. The upstream image is Alpine and already includes bash/jq/yq/curl.
RUN apk add --no-cache docker-cli gettext 2>/dev/null || \
    (apt-get update && apt-get install -y --no-install-recommends docker.io gettext-base && rm -rf /var/lib/apt/lists/*) || \
    echo "Could not install docker CLI - automatic synapse restart will be disabled"

COPY docker-entrypoint.sh /custom-entrypoint.sh
RUN chmod +x /custom-entrypoint.sh

ENTRYPOINT ["/custom-entrypoint.sh"]
