---
title: "STMNA Signal Install Guide"
repo: stmna-signal
prereq: "stmna-desk install guide, Core + Automation tiers"
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
| STMNA Desk, Core + Automation tiers (Steps 1-8) | [Desk install guide](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md) |
| STMNA Desk, Kokoro TTS (Step 10) -- for audio summaries | [Desk install guide, Step 10](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md#step-10-kokoro-tts-text-to-speech) |
| STMNA Desk, Forgejo (Step 11) -- for vault git sync | [Desk install guide, Step 11](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md#step-11-forgejo-git-hosting) |
| PostgreSQL running with `stmna_signal` database | Desk install guide, Step 4 |
| n8n running with custom image | Desk install guide, Step 7 |
| llama-swap running with at least one LLM | Desk install guide, Step 5 |
| Whisper server running | Desk install guide, Step 8 |
| Crawl4AI running -- for web article scraping | [Desk install guide, Step 13](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md#step-13-crawl4ai-web-scraping) |
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

## Step 2: Deploy NextCloud

NextCloud provides file storage with a WebDAV API. The Signal pipeline uses it for incoming file drops (books, documents) and delivering audio summaries.

In Dockge, create a new stack named `nextcloud`:

```yaml
# ============================================================
# STMNA Signal -- NextCloud (Sovereign Cloud Storage)
# Part of: stmna-signal install guide, Step 2
# Requires: stmna-net network
# ============================================================

x-podman:
  in_pod: false

services:
  nextcloud:
    # INFO: Sovereign cloud storage with WebDAV API for n8n file operations
    image: docker.io/library/nextcloud:30-apache
    container_name: nextcloud
    restart: always
    ports:
      # OPTIONAL -- change host port if 8090 conflicts
      - "8090:80"
    volumes:
      # NO ACTION NEEDED -- persistent data (files, config, database)
      - /home/stmna/data/nextcloud:/var/www/html
    environment:
      # USER INPUT REQUIRED -- admin credentials (set on first run only, ignored after)
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=YOUR_ADMIN_PASSWORD_HERE
      # NO ACTION NEEDED -- use built-in SQLite (sufficient for single-user/small-team)
      - SQLITE_DATABASE=nextcloud
      # USER INPUT REQUIRED -- your server's domain or IP (for trusted domains)
      # NOTE -- "nextcloud" is the container hostname, needed for n8n WebDAV access via stmna-net
      - NEXTCLOUD_TRUSTED_DOMAINS=YOUR_IP localhost nextcloud
      # OPTIONAL -- disable HTTPS enforcement for LAN-only access
      - OVERWRITEPROTOCOL=http
    networks:
      - default
      - stmna-net

networks:
  default: {}
  stmna-net:
    external: true
```

> **Required:** Set `NEXTCLOUD_ADMIN_PASSWORD` to a strong password. Generate one with `openssl rand -hex 16`.

> **Required:** Set `NEXTCLOUD_TRUSTED_DOMAINS` to your server's IP or domain (e.g., `10.0.10.54 localhost`). NextCloud rejects requests from untrusted domains.

**Expected result:** NextCloud is accessible at `http://YOUR_IP:8090`. Log in with the admin credentials you set above.

### Create the mcp-bot user

The Signal pipeline accesses NextCloud via WebDAV using a dedicated service account.

1. Log in to NextCloud as admin
2. Go to Users (top-right menu > Users)
3. Click "New user"
4. Username: `mcp-bot`, set a strong password
5. Save the password -- you will need it for n8n credential configuration

### Create the pipeline folder structure

1. Log in as `mcp-bot` (or create a shared folder as admin and share it with `mcp-bot`)
2. Create the following folder structure:

```
Pipeline/
  Incoming/    ← drop files here for processing
  Processed/   ← pipeline moves files here after processing
```

Verify WebDAV access from the n8n container:

```bash
podman exec n8n wget -q -O- \
  --method=PROPFIND \
  --header='Depth: 1' \
  --header='Authorization: Basic BASE64_CREDENTIALS' \
  'http://nextcloud/remote.php/webdav/'
```

> **Note:** Generate `BASE64_CREDENTIALS` with: `echo -n 'mcp-bot:YOUR_PASSWORD' | base64`

**Expected result:** An XML response listing the root directory contents.

---

## Step 3: Apply the Database Schema

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

## Step 4: Configure n8n Credentials

Open n8n at `http://YOUR_IP:5678` and create the following credentials. Go to Settings > Credentials > Add Credential for each.

| Credential Name | Type | Values |
|----------------|------|--------|
| Postgres Signal | PostgreSQL | Host: `postgres-voice`, Port: `5432`, Database: `stmna_signal`, User: `voice`, Password: your postgres password |
| Signal API | HTTP Header Auth | Name: `Authorization`, Value: (leave empty unless you set an API key on signal-cli) |
| NextCloud account | WebDAV | Base URL: `http://nextcloud/remote.php/webdav/`, User: `mcp-bot`, Password: your mcp-bot password |

> **Required:** The credential name "Postgres Signal" must match exactly. The workflows reference credentials by name.

> **Note:** Kokoro TTS runs without credentials (HTTP calls within the container network).

### Configure Git access for vault writes

The Signal Worker writes processed notes to a Git repository on Forgejo. This requires a Personal Access Token (PAT) for HTTPS authentication.

1. In Forgejo, go to your user Settings > Applications > Generate New Token
2. Token name: `n8n-vault` (or any name)
3. Permissions: `repository: Read and Write`
4. Copy the token -- you cannot view it again after creation

5. Configure the Git remote inside the n8n container. The vault directory must be a Git repository cloned from Forgejo:

```bash
# Mount your output directory as /vault in the n8n compose file first (see Desk Step 7)
# Then clone the repo into that directory:
cd /path/to/your/output/directory
git clone https://YOUR_FORGEJO_USER:YOUR_TOKEN@YOUR_IP:3300/YOUR_ORG/YOUR_REPO.git .
```

6. Set the Git safe directory inside the n8n container:

```bash
podman exec n8n sh -c 'mkdir -p /home/node/.n8n && echo "[safe]
	directory = /vault" > /home/node/.n8n/.gitconfig'
```

> **Note:** The PAT is embedded in the Git remote URL. This is standard for containerized Git access where SSH key management adds unnecessary complexity.

> **Note:** The `safe.directory` setting is required because `/vault` is owned by a different UID than the `node` user inside the container.

---

## Step 5: Import Workflows

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

## Step 6: Smoke Test

### Test 1: Database connectivity

Open the Signal Ingestion workflow in n8n. Click on any PostgreSQL node and click "Test". It should connect without errors.

### Test 2: Signal message receive

Send a test message to the linked Signal number from another device. Check signal-cli-rest-api:

```bash
curl -s http://localhost:8080/v1/receive
```

**Expected result:** A JSON array containing your test message.

### Test 3: NextCloud WebDAV

Upload a test file from the n8n container:

```bash
podman exec n8n wget -q -O- \
  --method=PUT \
  --header='Authorization: Basic BASE64_CREDENTIALS' \
  --body-data='test content' \
  'http://nextcloud/remote.php/webdav/Pipeline/Incoming/test.txt'
```

**Expected result:** No output (HTTP 201 Created). Verify the file appears in NextCloud web UI.

### Test 4: Whisper connectivity

Verify the Whisper-signal instance (used for YouTube/podcast transcription) is reachable from n8n:

```bash
podman exec n8n wget -q -O- 'http://whisper-signal:8084/v1/models'
```

**Expected result:** A JSON response listing the loaded model.

### Test 5: Crawl4AI connectivity

Verify Crawl4AI is reachable from n8n:

```bash
podman exec n8n wget -q -O- 'http://crawl4ai:11235/health'
```

**Expected result:** A JSON response indicating the service is healthy.

### Test 6: Full pipeline (manual trigger)

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

### NextCloud: "Access through untrusted domain"

**Cause:** You are accessing NextCloud via an IP or domain not listed in `NEXTCLOUD_TRUSTED_DOMAINS`.

**Fix:** Update `NEXTCLOUD_TRUSTED_DOMAINS` in the compose file to include the IP or domain you are using. Restart the stack.

### NextCloud: WebDAV returns 401 Unauthorized

**Cause:** The mcp-bot credentials are wrong, or the user does not exist.

**Fix:** Verify the credentials by logging into the NextCloud web UI as `mcp-bot`. Check the password matches what you configured in the n8n NextCloud credential.

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
| NextCloud (file drops) | Any WebDAV-compatible storage. Update the WebDAV URLs in Signal_NextCloud workflow. |
| signal-cli-rest-api | Same image works anywhere. Just needs a linked Signal account. |

This path is community-supported. The STMNA team validates against Desk only.

---

## What's Next

- [Signal workflow architecture](../workflows/README.md) -- understand how the pipeline works
- [Desk install guide](https://f.slowdawn.cc/stmna-io/stmna-desk/src/branch/main/docs/install-guide.md) -- full infrastructure setup
- [Voice install guide](https://f.slowdawn.cc/stmna-io/stmna-voice/src/branch/main/docs/install-guide.md) -- add voice transcription
