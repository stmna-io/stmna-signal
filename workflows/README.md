# STMNA Signal — Workflow Reference

This directory contains the four n8n workflows that make up the STMNA Signal pipeline. They process content from Signal messages, webhooks, and NextCloud drops into structured Obsidian vault notes with optional translation and text-to-speech audio.

---

## Architecture

```
Signal / Webhook / NextCloud
        │
        ▼
┌─────────────────────┐
│  Signal_Ingestion   │  Receives messages, parses commands, deduplicates, queues work
└──────────┬──────────┘
           │ PostgreSQL pipeline_queue
           ▼
┌─────────────────────┐
│   Signal_Worker     │  Downloads, transcribes, summarizes, translates, generates TTS
│   (77 nodes)        │  Writes vault notes, uploads audio, sends Signal response
└──────────┬──────────┘
           │
           ├──────────────────────────────┐
           │                              │
           ▼                              ▼
┌─────────────────────┐      ┌────────────────────────┐
│  Signal_Cleanup     │      │   Signal_NextCloud      │
│  (scheduled)        │      │   (file drop input)     │
└─────────────────────┘      └────────────────────────┘
```

| File | Workflow | Nodes | Trigger | Purpose |
|------|----------|-------|---------|---------|
| `signal-ingestion.json` | Signal_Ingestion | 34 | Schedule (5s poll) | Receives Signal messages, parses command flags, checks content cache, queues to PostgreSQL |
| `signal-worker.json` | Signal_Worker | 77 | Schedule (10s poll) | Processes queued jobs: YouTube download + transcription, web scraping, summarization, TEaR translation, TTS audio generation, vault note writing, Signal response |
| `signal-cleanup.json` | Signal_Cleanup | 9 | Schedule (5 AM + 8 AM) | Purges expired cache entries, delivers deferred responses |
| `signal-nextcloud.json` | Signal_NextCloud | 14 | Schedule (60s poll) | Monitors NextCloud Inbox/ and Translate/ folders for file drops |

---

## Content Types

The Worker handles seven content types, routed by the Content Switch node:

| Type | Source | Processing |
|------|--------|------------|
| YouTube | URL detection | yt-dlp download, Whisper transcription, Qwen summarization |
| Web | URL detection | Crawl4AI scraping, Qwen summarization |
| Braindump | `braindump` flag | Direct text processing, Qwen summarization |
| VoiceNote | Signal audio attachment | FFmpeg conversion, Whisper transcription, Qwen summarization |
| LocalVideo | Signal video attachment | FFmpeg audio extraction, Whisper transcription, Qwen summarization |
| LocalAudio | Signal audio file | FFmpeg conversion, Whisper transcription, Qwen summarization |
| TranslateBook | `book` flag + EPUB | EPUB chapter extraction, TEaR 3-pass translation (Translate, Evaluate, Revise) |

## Command Flags

Users send these with URLs or content to control processing:

| Flag | Effect |
|------|--------|
| `quick` | Shorter summary |
| `deep` | Extended analysis |
| `transcript` | Return raw transcript only |
| `braindump` | Treat text as braindump (no URL needed) |
| `book` | EPUB translation mode (TEaR 3-pass) |
| `translate fr` / `en` / `nl` | Translate summary to specified language |
| `tts` | Generate audio version via Kokoro TTS |
| `tts fr` | Generate TTS in French |

Flags are combinable: `tts fr https://youtube.com/...` translates to French and generates audio.

---

## Prerequisites

### Services

All services must be reachable from your n8n instance:

| Service | Used by | Required? |
|---------|---------|-----------|
| [signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api) | Ingestion | Yes |
| PostgreSQL 15+ with 4 tables | Ingestion, Worker, Cleanup, NextCloud | Yes |
| [llama-swap](https://github.com/mostlygeek/llama-swap) or OpenAI-compatible API | Worker | Yes |
| [whisper.cpp server](https://github.com/ggerganov/whisper.cpp) | Worker | Yes |
| [crawl4ai](https://github.com/unclecode/crawl4ai) | Worker (web articles) | Yes |
| [Kokoro TTS](https://github.com/remsky/kokoro-fastapi) | Worker (audio generation) | For TTS features |
| NextCloud (WebDAV) | Worker, NextCloud | For audio delivery and file drops |
| [SearXNG](https://github.com/searxng/searxng) | Worker | Recommended |
| Vault Ops n8n workflow | Worker | For vault note writing |

### n8n Requirements

- n8n **1.75+** (workflow format v2)
- Custom n8n image with `ffmpeg` and `yt-dlp` installed (required for YouTube audio extraction and audio conversion)
- Environment variable: `NODE_FUNCTION_ALLOW_BUILTIN=fs,child_process,path`
- Recommended: `N8N_RUNNERS_TASK_TIMEOUT=43200` for long book translation jobs (12 hours)

See the [docker/](../docker/) directory for a ready-to-use n8n Dockerfile.

### Database

The pipeline uses a PostgreSQL database (`stmna_signal`) with four tables:

- `pipeline_users` — registered Signal users and preferences
- `pipeline_queue` — job queue with status tracking
- `content_cache` — deduplicated content (Layer 1: extraction results)
- `content_variants` — translated/transformed versions (Layer 2: transformation results)

```bash
psql -U postgres -d stmna_signal -f ../sql/schema.sql
```

---

## Import Instructions

1. In n8n, go to **Settings > Import workflow**
2. Import workflows **in this order** (dependencies flow downward):
   1. `signal-cleanup.json` — no dependencies on other workflows
   2. `signal-nextcloud.json` — writes to the same queue table as Ingestion
   3. `signal-ingestion.json` — receives messages, queues work
   4. `signal-worker.json` — reads from queue, calls all external services
3. For each workflow, reassign credentials after import (see below)
4. **Activate** in reverse order: Worker first, then Ingestion, then Cleanup

---

## Required Credentials

Create these credential types in n8n (**Settings > Credentials > Add credential**), then reassign them to each workflow after import.

### `Postgres` credential

Point to your `stmna_signal` database. Used by every workflow.

| Workflow | Nodes using this credential |
|----------|-----------------------------|
| Signal_Ingestion | Resolve Identity, Cache Check, Queue Job, Queue Braindump |
| Signal_Worker | Pick Job, Get Sender Info, Exec Cache Upsert, Mark Done, Mark Failed, Save Deferred Response |
| Signal_NextCloud | Cache Check, Queue Job, Queue Dedup Check |
| Signal_Cleanup | Purge Expired Cache, Stats, Fetch Pending Responses, Mark Responses Sent |

### `Nextcloud` credential

Used for WebDAV file operations. Required for TTS audio upload and the NextCloud input path.

| Workflow | Nodes using this credential |
|----------|-----------------------------|
| Signal_Worker | NC Upload Audio, NC Upload Translated, Move NC to Processed |
| Signal_NextCloud | List Inbox Files, Download File, Move to Processed, List Translate Files |

---

## Environment Variables

Copy `.env.example` to `.env` at the repo root and fill in all values. Key variables:

```env
# Core services
SIGNAL_API_URL=http://your-signal-api:8082
LLAMA_SWAP_URL=http://your-llama-swap:8081
WHISPER_URL=http://your-whisper:8084
CRAWL4AI_URL=http://your-crawl4ai:11235

# TTS (for audio generation)
KOKORO_TTS_URL=http://your-kokoro-tts:8880
KOKORO_DEFAULT_VOICE_EN=af_heart
KOKORO_DEFAULT_VOICE_FR=ff_siwis

# Audio delivery
NEXTCLOUD_AUDIO_SIGNALS_PATH=/Shared/Pipeline/Audio/signals
NEXTCLOUD_AUDIO_BOOKS_PATH=/Shared/Pipeline/Audio/books
```

See `.env.example` for the full list with descriptions.

---

## How It Works

### Ingestion to Worker Flow

1. A Signal message arrives containing a URL (or text with a command flag)
2. Signal_Ingestion parses command flags (`tts`, `translate fr`, `book`, etc.)
3. Checks PostgreSQL `content_cache` for a cache hit on the content key
4. Cache miss: inserts a row into `pipeline_queue` with status `pending`
5. Signal_Worker polls the queue every 10 seconds, picks up the job
6. Worker detects content type (YouTube, web, braindump, voice, book) and routes to the appropriate processing chain
7. Content is downloaded, transcribed (if audio/video), and summarized by Qwen 3.5-35B
8. If translation was requested: TEaR 3-pass pipeline runs (Translate at temp 0.3, Evaluate at temp 0.1, Revise at temp 0.2)
9. If TTS was requested: summary is rewritten for spoken delivery, sent to Kokoro TTS, MP3 uploaded to NextCloud
10. A vault note is written via the Vault Ops webhook
11. A confirmation reply (with optional audio attachment) is sent back to the Signal sender

### Two-Layer Caching

- **Layer 1 (content_cache):** Stores extraction results (downloads, transcriptions, scrapes). Expensive to produce, shared across users.
- **Layer 2 (content_variants):** Stores transformation results (translations, TTS rewrites). Lightweight to produce, user/language-specific.

Cache hit on Layer 1 skips extraction entirely. Cache hit on Layer 2 skips transformation. A URL processed once for one user can be translated for another user at minimal cost.

### Cleanup

- Runs at 5 AM daily: purges cache entries older than 7 days
- Runs at 8 AM daily: delivers deferred responses (content that arrived outside delivery hours)

---

## Adapting to Your Setup

These workflows were built for a specific hardware stack (AMD Strix Halo, 128GB unified memory, llama-swap for model routing). If you're running a different inference backend:

- Replace `LLAMA_SWAP_URL` with any OpenAI-compatible endpoint
- Adjust model names in the Worker's Code nodes to match what you have loaded
- The whisper transcription step works with any STT API that returns a transcript string
- Kokoro TTS uses the OpenAI-compatible `/v1/audio/speech` endpoint, so any TTS with that interface works
- The pipeline is modular: each workflow is independently testable via its trigger

For the full architecture reference, see the [Signal Pipeline PRD](https://github.com/stmna-io/stmna-signal) in the project documentation.
