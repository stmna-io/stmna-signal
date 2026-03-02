# STMNA Signal — Workflow Reference

This directory contains the four n8n workflows that make up the STMNA Signal pipeline. Import them in the order listed below — they're designed to work together.

---

## Workflow Overview

```
Signal / Webhook / File
        │
        ▼
┌─────────────────────┐
│  Signal_Ingestion   │  Receives messages, deduplicates, queues work
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Signal_Worker     │  Processes URLs (YouTube, web), summarizes, writes to vault
└──────────┬──────────┘
           │
           ├──────────────────────────────┐
           │                              │
           ▼                              ▼
┌─────────────────────┐      ┌────────────────────────┐
│  Signal_Cleanup     │      │   Signal_NextCloud      │
│  (scheduled)        │      │   (NextCloud input)     │
└─────────────────────┘      └────────────────────────┘
```

| File | Workflow | Trigger | Purpose |
|------|----------|---------|---------|
| `signal-ingestion.json` | Signal_Ingestion | Webhook (Signal API) | Receives messages, checks content cache, queues to PostgreSQL |
| `signal-worker.json` | Signal_Worker | Webhook (internal queue) | Fetches queue, runs YouTube or web pipeline, writes vault note |
| `signal-nextcloud.json` | Signal_NextCloud | Webhook (NextCloud) | Alternate input path for file drops via NextCloud |
| `signal-cleanup.json` | Signal_Cleanup | Schedule (cron) | Daily cache purge and deferred delivery |

---

## Prerequisites

### Services

All services must be reachable from your n8n instance:

| Service | Used by | Required? |
|---------|---------|-----------|
| [signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api) | Ingestion | Yes |
| PostgreSQL 15+ | Ingestion, Worker, Cleanup | Yes |
| [llama-swap](https://github.com/mostlygeek/llama-swap) or compatible OpenAI API | Worker | Yes |
| [whisper.cpp server](https://github.com/ggerganov/whisper.cpp) | Worker (YouTube audio) | Yes |
| [crawl4ai](https://github.com/unclecode/crawl4ai) | Worker (web articles) | Yes |
| [SearXNG](https://github.com/searxng/searxng) | Worker | Recommended |
| NextCloud | Signal_NextCloud | Optional |

### n8n Requirements

- n8n **1.75+** (workflow format v2)
- Custom n8n image with `ffmpeg` and `yt-dlp` installed (required for YouTube audio extraction)
- Environment variable: `NODE_FUNCTION_ALLOW_BUILTIN=fs,child_process,path`
- Recommended: `N8N_RUNNERS_TASK_TIMEOUT=21600` for long translation jobs

See the [docker/](../docker/) directory for a ready-to-use n8n Dockerfile.

### Database

The pipeline uses a PostgreSQL database (`stmna_signal`) with two tables:

```bash
psql -U postgres -d stmna_signal -f ../sql/schema.sql
```

See [sql/](../sql/) for the full schema.

---

## Import Instructions

1. In n8n, go to **Settings → Import workflow**
2. Import workflows **in this order:**
   1. `signal-ingestion.json`
   2. `signal-worker.json`
   3. `signal-cleanup.json`
   4. `signal-nextcloud.json` (optional)
3. For each workflow, reassign credentials after import (see below)
4. **Activate** Signal_Ingestion and Signal_Worker first, then Cleanup

---

## Required Credentials

Create these credential types in n8n (**Settings → Credentials → Add credential**), then reassign them to each workflow after import.

### `Postgres` credential
Point to your `stmna_signal` database. Used by every workflow.

| Workflow | Nodes using this credential |
|----------|-----------------------------|
| Signal_Ingestion | Resolve Identity, Cache Check, Queue Job, Queue Braindump |
| Signal_Worker | Pick Job, Get Sender Info, Exec Cache Upsert, Mark Done, Mark Failed, Save Deferred Response |
| Signal_NextCloud | Cache Check, Queue Job, Queue Dedup Check |
| Signal_Cleanup | Purge Expired Cache, Stats, Fetch Pending Responses, Mark Responses Sent |

### `Nextcloud` credential
Used for WebDAV file operations (list, download, move files in NextCloud). Only required if you use the Signal_NextCloud workflow or the NextCloud delivery path in Signal_Worker.

| Workflow | Nodes using this credential |
|----------|-----------------------------|
| Signal_Worker | NC Upload Translated, Move NC to Processed |
| Signal_NextCloud | List Inbox Files, Download File, Move to Processed, Move Cached to Processed, List Translate Files |

To create credentials: **Settings → Credentials → Add credential**

---

## Environment Variables

Copy `.env.example` to `.env` at the repo root and fill in all values. See `.env.example` for descriptions of each variable.

Key variables the workflows depend on (configure in n8n or your compose file):

```env
SIGNAL_API_URL=http://your-signal-api:8082
LLAMA_SWAP_URL=http://your-llama-swap:8081
WHISPER_URL=http://your-whisper:8083
CRAWL4AI_URL=http://your-crawl4ai:11235
```

---

## How It Works

**Ingestion → Worker flow:**

1. A Signal message arrives (via signal-cli webhook) containing a URL
2. Signal_Ingestion checks PostgreSQL for a content cache hit
3. Cache miss: inserts a row into `pipeline_queue` with status `pending`
4. Signal_Ingestion fires a webhook to Signal_Worker
5. Signal_Worker detects content type (YouTube vs web), runs the appropriate sub-pipeline
6. Output: a formatted Obsidian vault note written via the Vault Ops webhook
7. A confirmation reply is sent back to the Signal sender

**Cleanup:**

- Runs at 5 AM daily — purges cache entries older than 7 days
- Handles deferred delivery (content that arrived outside delivery hours)

---

## Prompts

All LLM prompts are stored in [../prompts/](../prompts/) as `.md` files, not hardcoded in workflows. This makes them easy to tune without touching the workflow JSON.

---

## Adapting to Your Setup

These workflows were built for a specific hardware stack (AMD Strix Halo + llama-swap). If you're running a different inference backend:

- Replace `LLAMA_SWAP_URL` with any OpenAI-compatible endpoint
- Adjust model names to match what you have loaded
- The whisper transcription step can be replaced with any STT API that returns a transcript string

The pipeline is intentionally modular — each workflow is independently testable via its webhook trigger.
