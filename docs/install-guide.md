---
title: "STMNA Signal Install Guide"
repo: stmna-signal
prereq: "stmna-desk install guide sections 1-7"
validated: staging
updated: 2026-03-05
---

# STMNA Signal Install Guide

> By the end of this guide, you will have the STMNA Signal content pipeline running: send a YouTube URL or web link via Signal, get back a structured summary with optional translation and TTS audio.
>
> Tested on Ubuntu 24.04 LTS, deployed via Dockge on a staging VM (10.0.10.55) during SB-06.

## Prerequisites

| Requirement | Where to get it |
|-------------|----------------|
| STMNA Desk stack (Steps 1-7) | [Desk install guide](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md) |
| PostgreSQL running with `stmna_signal` database | Desk install guide, Step 4 |
| n8n running with custom image | Desk install guide, Step 7 |
| llama-swap running with at least one LLM | Desk install guide, Step 5 |
| Whisper server running | Desk install guide, Step 6 |
| A Signal account on your phone | [signal.org](https://signal.org) |

If installing on other infrastructure: see [Running on Other Infrastructure](#running-on-other-infrastructure) below.

---

## Step 1: Deploy signal-cli-rest-api

The Signal pipeline receives and sends messages through `signal-cli-rest-api`, a containerized Signal client that exposes a REST API.

In Dockge, create a new stack named `signal-cli`:

```yaml
# ============================================================
# STMNA Signal -- signal-cli-rest-api
# Part of: stmna-signal install guide, Step 1
# Requires: stmna-net network
# ============================================================

x-podman:
  in_pod: false

services:
  signal-cli-rest-api:
    # INFO: Containerized Signal client with REST API for sending/receiving messages
    image: docker.io/bbernhard/signal-cli-rest-api:latest
    container_name: signal-cli-rest-api
    restart: always
    ports:
      # OPTIONAL -- change host port if 8080 conflicts
      - "8080:8080"
    environment:
      # OPTIONAL -- json-rpc mode recommended for speed
      - MODE=json-rpc
      # USER INPUT REQUIRED -- run `id -u` to get your UID
      - SIGNAL_CLI_UID=1000
      # USER INPUT REQUIRED -- run `id -g` to get your GID
      - SIGNAL_CLI_GID=1000
      # OPTIONAL -- auto-receive keeps message queue fresh
      - AUTO_RECEIVE_SCHEDULE=0 * * * *
    volumes:
      # NO ACTION NEEDED -- Signal config and keys persist here
      - ./signal-cli-config:/home/.local/share/signal-cli
    networks:
      - default
      - stmna-net

networks:
  default: {}
  stmna-net:
    external: true
```

> **Required:** Set `SIGNAL_CLI_UID` and `SIGNAL_CLI_GID` to match your `stmna` user. Run `id -u` and `id -g` to check. This is critical for rootless Podman volume permissions.

### Link your Signal account

After deploying, open your browser to:

```
http://YOUR_IP:8080/v1/qrcodelink?device_name=signal-api
```

Scan the QR code from your phone: Signal > Settings > Linked Devices > (+).

> **Note:** The signal-cli config persists in the `signal-cli-config` volume. You can recreate the container without re-linking. If you already have signal-cli running on bare metal, copy `~/.local/share/signal-cli` into the container volume to migrate without re-linking.

Verify the link worked:

```bash
curl -s http://localhost:8080/v1/about
```

**Expected result:** A JSON response showing your linked Signal number.

---

## Step 2: Apply the Database Schema

The Signal pipeline uses four PostgreSQL tables: `pipeline_users`, `pipeline_queue`, `content_cache`, and `content_variants`.

Copy `sql/schema.sql` from the stmna-signal repo to your server, then apply it:

```bash
podman exec -i postgres-voice psql -U voice -d stmna_signal < schema.sql
```

**Expected result:** A series of `CREATE TABLE`, `CREATE SEQUENCE`, `CREATE INDEX`, and `GRANT` statements with no errors.

Verify the tables exist:

```bash
podman exec postgres-voice psql -U voice -d stmna_signal -c "\dt"
```

**Expected result:**

```
              List of relations
 Schema |       Name        | Type  | Owner
--------+-------------------+-------+-------
 public | content_cache     | table | voice
 public | content_variants  | table | voice
 public | pipeline_queue    | table | voice
 public | pipeline_users    | table | voice
```

---

## Step 3: Configure n8n Credentials

Open n8n at `http://YOUR_IP:5678` and create the following credentials. Go to Settings > Credentials > Add Credential for each.

| Credential Name | Type | Values |
|----------------|------|--------|
| Postgres Signal | PostgreSQL | Host: `postgres-voice`, Port: `5432`, Database: `stmna_signal`, User: `voice`, Password: your postgres password |
| Signal API | HTTP Header Auth | Name: `Authorization`, Value: (leave empty unless you set an API key on signal-cli) |

> **Required:** The credential name "Postgres Signal" must match exactly. The workflows reference credentials by name.

> **Note:** Additional credentials are needed for optional features: NextCloud account (for file ingestion), Kokoro TTS runs without credentials (HTTP calls within the container network).

---

## Step 4: Import Workflows

Import the workflows in this order:

1. `signal-ingestion.json`
2. `signal-worker.json`
3. `signal-cleanup.json`
4. `signal-nextcloud.json` (optional, for NextCloud file ingestion)

In n8n, go to Workflows > Import from File for each JSON file from the `workflows/` directory.

After importing, open each workflow and **re-link credentials manually**:

1. Open the workflow in the n8n editor
2. Click on each PostgreSQL node (they will show a red "credential missing" warning)
3. Select "Postgres Signal" from the credential dropdown
4. Save the workflow

> **Why:** Sanitized workflow files contain placeholder credential IDs that do not exist on your instance. The n8n UI import preserves these invalid references, so you must re-link each credential node to your local "Postgres Signal" credential.

Verify after re-linking:
- All credential nodes show green (no warnings)
- The PostgreSQL nodes point to "Postgres Signal"

> **Note:** Do not activate the workflows yet. Complete the smoke test first.

---

## Step 5: Smoke Test

### Test 1: Database connectivity

Open the Signal Ingestion workflow in n8n. Click on any PostgreSQL node and click "Test". It should connect without errors.

### Test 2: Signal message receive

Send a test message to the linked Signal number from another device. Check signal-cli-rest-api:

```bash
curl -s http://localhost:8080/v1/receive
```

**Expected result:** A JSON array containing your test message.

### Test 3: Full pipeline (manual trigger)

Insert a test job directly into the queue:

```bash
podman exec postgres-voice psql -U voice -d stmna_signal -c "
INSERT INTO pipeline_users (name, role) VALUES ('test-user', 'admin');
INSERT INTO pipeline_queue (url, content_type, sender, status)
VALUES ('https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'youtube', 1, 'pending');
"
```

Activate the Signal Worker workflow, wait for it to pick up the job (polls every 10 seconds), then check the execution log in n8n.

> **Note:** This test requires llama-swap to be running with a loaded model (for summarization) and Whisper to be running (for transcription). Without these, the workflow will fail at the inference step, which is expected if you do not have GPU hardware.

---

## Troubleshooting

### signal-cli-rest-api: QR code page shows error

**Cause:** The container may still be starting up. signal-cli initialization takes 10-30 seconds on first run.

**Fix:** Wait 30 seconds and refresh the page.

### n8n credential test fails: "Connection refused" to postgres-voice

**Cause:** The n8n container cannot reach the PostgreSQL container. Both must be on the `stmna-net` network.

**Fix:** Verify both containers are on `stmna-net`:

```bash
podman network inspect stmna-net | grep -E '"Name"'
```

Both `n8n` and `postgres-voice` should appear in the output.

### Workflow import error: "request/body must NOT have additional properties"

**Cause:** The n8n API rejects workflow JSON files that contain extra fields (e.g., `active`, `isArchived`, `staticData`).

**Fix:** Strip the JSON to only `name`, `nodes`, `connections`, and `settings` before importing via the API. Or use the n8n UI import (Workflows > Import from File), which handles this automatically.

---

## Running on Other Infrastructure

This guide is written and tested against STMNA Desk. If running on other infrastructure, adapt the following:

| Dependency | What to substitute |
|------------|-------------------|
| llama-swap (local inference) | Any OpenAI-compatible inference endpoint (OpenAI API, Ollama, vLLM). Update the HTTP URLs in Signal Worker Code nodes. |
| Whisper server (local transcription) | Any Whisper-compatible API (OpenAI Whisper API, Groq). Update the Whisper Transcribe node URLs. |
| Kokoro TTS (local text-to-speech) | Any OpenAI-compatible TTS endpoint. Update the TTS Generate Audio node URL. |
| PostgreSQL with PGVector | Any PostgreSQL 15+ instance with the `vector` extension. |
| signal-cli-rest-api | Same image works anywhere. Just needs a linked Signal account. |

This path is community-supported. The STMNA team validates against Desk only.

---

## What's Next

- [Signal workflow architecture](../workflows/README.md) -- understand how the pipeline works
- [Desk install guide](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md) -- full infrastructure setup
- [Voice install guide](https://f.slowdawn.cc/stmna-io/stmna-voice/src/branch/main/docs/install-guide.md) -- add voice transcription
