# Signal Bot Setup Guide

<!-- TODO: Write full Signal bot setup guide for SB-07 session -->
<!-- Content: signal-cli-rest-api deployment on VPS, phone number registration,
     linking secondary device, webhook configuration, n8n webhook URL setup,
     bearer token auth, testing with curl, common errors -->

## Placeholder

This document will cover:

### signal-cli-rest-api

- Docker/Podman deployment on your VPS
- Phone number registration (SMS verification)
- Secondary device linking (so your real Signal app still works)
- REST API configuration

### n8n Webhook Setup

- Webhook URL configuration in Signal_Ingestion workflow
- Linking signal-cli to n8n webhook endpoint
- Testing: send a URL → verify it reaches n8n

### Authentication

- Bearer token setup for webhook security
- Caddy configuration to protect the webhook endpoint

### Troubleshooting

- Common registration errors
- Device linking issues
- Webhook not receiving messages

Coming in SB-07 session.
