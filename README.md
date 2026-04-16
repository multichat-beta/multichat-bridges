# MultiChat Bridge Infrastructure

This repository contains the configuration files and Dockerfiles for the Matrix-based bridge infrastructure that powers MultiChat's messaging integrations.

## What's here

- Synapse homeserver configuration
- Bridge configurations for WhatsApp, Telegram, Messenger, and Google Messages

## What's NOT here

MultiChat's client app, backend, and AI features are proprietary and not included in this repository.

## Upstream projects

We run these projects unmodified. Source code is available at:

- [Synapse](https://github.com/element-hq/synapse) (AGPLv3)
- [mautrix-whatsapp](https://github.com/mautrix/whatsapp) (AGPLv3)
- [mautrix-telegram](https://github.com/mautrix/telegram) (AGPLv3)
- [mautrix-meta](https://github.com/mautrix/meta) (AGPLv3)
- [mautrix-gmessages](https://github.com/mautrix/gmessages) (AGPLv3)

## License

The configuration files in this repository are provided under AGPLv3 to match the upstream projects.
