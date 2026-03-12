
<div align="center">
  <!-- TODO: Replace with actual banner -->
  <!-- Banner: Deep Navy (#1A1A2E) background, Ember Orange (#FF8C42) accents -->
  <!-- STMNA pixel S logo + Signal wordmark -->

  <h1>STMNA Signal</h1>
  <h3>Content Intelligence Pipeline</h3>
  <p><em>Send any URL. Get back a structured knowledge note. Everything runs on your hardware.</em></p>

  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
  [![Built on AMD](https://img.shields.io/badge/Built%20on-AMD%20Strix%20Halo-ED1C24)](https://www.amd.com)
  [![Powered by n8n](https://img.shields.io/badge/Powered%20by-n8n-FF6D5A)](https://n8n.io)
  [![Framework Desktop](https://img.shields.io/badge/Hardware-Framework%20Desktop-000000)](https://frame.work)
  ![Status](https://img.shields.io/badge/Status-Phase%201%20Live-brightgreen)

  <br/>

  [Architecture](#architecture) · [Performance](#performance) · [Setup](#setup) · [Documentation](#documentation)
</div>

---

<!-- TODO: Hero GIF: 15-20 second demo: send YouTube URL via Signal → receive vault note -->

You find a video worth watching. You save an article to read later. A week later, none of it is accessible. The tab is closed, the video is somewhere in history, and the insight that felt important at the time has completely evaporated. You processed 30 pieces of content and retained almost none of it.

STMNA Signal is how I solved that for myself. Send a YouTube URL, a web article, or a file via Signal messenger (or webhook, or NextCloud drop) and a few minutes later you have a structured note in your Obsidian vault: key points extracted, context preserved, tagged and queryable. A 42-minute video becomes a 2-minute read. A 2h30m documentary becomes 5 minutes. The full transcript is kept alongside, for when you want to go deeper.

The pipeline runs entirely on local hardware. No content leaves the machine. Transcripts are not uploaded anywhere. Summaries are not sent to a cloud API. The reasoning is straightforward: if you're building a knowledge base meant to represent how you think, it should stay with you. Not out of paranoia, but because some things are worth keeping. Every architectural decision in this codebase reflects that.

This repo contains the n8n workflow exports, database schema, and setup documentation for the live pipeline. If you're starting from scratch, begin with [STMNA Desk](https://github.com/stmna-io/stmna-desk) for the hardware and infrastructure stack, then come back here for the Signal-specific layer.

---

## Architecture

```
Signal / Webhook / NextCloud
            |
            v
     Signal_Ingestion
     (deduplicate, queue)
            |
            v
      Signal_Worker
       /           \
  YouTube          Web
  pipeline         pipeline
     |                |
     v                v
 whisper.cpp      Crawl4AI
 transcription    extraction
     |                |
     +--------+-------+
              |
              v
       Qwen summarization
              |
              v
       Obsidian vault note
       (30-SIGNALS/ folder)
```

### Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Orchestration | n8n (self-hosted) | Visual workflow automation |
| LLM inference | llama-swap + Qwen3.5-35B | Summarization, classification |
| Transcription | whisper.cpp (Vulkan) | large-v3-turbo, GPU-accelerated |
| Web scraping | Crawl4AI | Full article extraction |
| Ad filtering | SponsorBlock API | Two-layer: timestamp skip + prompt filter |
| Messaging | signal-cli-rest-api | Mobile-first input |
| Knowledge base | Obsidian | Markdown + YAML frontmatter |
| Cache / Queue | PostgreSQL | Deduplication, job queue, deferred delivery |
| Hardware | Framework Desktop | AMD Strix Halo, 128GB unified memory |

### Why Vulkan and not CUDA

The standard transcription choice for Python-based pipelines is WhisperX. When evaluating it on gfx1151 (AMD Strix Halo), it turned out to be fundamentally CUDA-dependent with no clean path to native support. Rather than forcing compatibility layers, we switched to whisper.cpp with Vulkan, which runs natively on the hardware and hit performance targets from the first test.

This validated the broader approach: Vulkan for inference (llama.cpp, whisper.cpp), ROCm for PyTorch-dependent ML when needed, all on the same chip. No CUDA required anywhere in the live stack. Cloud-based transcription APIs are faster to set up, and are a reasonable choice if you're not running AMD hardware or if you're prototyping. For a permanent knowledge base processing personal content, local wins.

---

## Performance

Measured on AMD Ryzen AI Max+ 395 (Strix Halo), 128GB unified, Radeon 8060S (gfx1151).

| Content | Duration | End-to-end | Stack |
|---------|---------|-----------|-------|
| YouTube short | 3.5 min | 25 seconds | whisper large-v3-turbo Q5 + Qwen3-30B |
| YouTube medium | 42 min | 118 seconds | whisper large-v3-turbo Q5 + Qwen3-30B |
| YouTube long | 2h 29min | 284 seconds | whisper large-v3-turbo Q5 + Qwen3-30B |
| Web article | any | under 30 seconds | Crawl4AI + Qwen3-30B |
| Cache hit | any | under 1 second | PostgreSQL |

The bottleneck is transcription, not summarization. Whisper large-v3-turbo on Vulkan processes audio at roughly 40x real-time on Strix Halo. Inference time for summarization adds 10-20 seconds on top.

---

## Setup

> Designed for and tested on [STMNA Desk](https://github.com/stmna-io/stmna-desk)
> (AMD Ryzen AI Max+ 395, 128GB unified memory). Can be adapted to any Linux system
> with the required services (n8n, whisper.cpp, llama.cpp, PostgreSQL).

### Network Requirements

STMNA Signal receives messages via webhooks, which require HTTPS endpoints reachable from the internet. If your server is behind a home network or firewall, you'll need a tunnel or reverse proxy. See [STMNA Desk: Remote Access](https://github.com/stmna-io/stmna-desk/blob/main/docs/remote-access.md) for options including Cloudflare Tunnels, Tailscale Funnel, and VPS-based reverse proxies.

### Prerequisites

- [STMNA Desk](https://github.com/stmna-io/stmna-desk) running (or equivalent: AMD GPU with Vulkan, llama-swap or any OpenAI-compatible endpoint, whisper.cpp server, n8n with ffmpeg)
- Signal number registered with signal-cli-rest-api (optional: webhook and NextCloud inputs work without it)
- Obsidian vault or any markdown-based knowledge system

### 1. Import the workflows

See [workflows/README.md](workflows/README.md) for the full import walkthrough: workflow order, required credentials, credential assignment per node, and environment variable reference.

### 2. Set up the database

```bash
createdb -U postgres stmna_signal
psql -U postgres -d stmna_signal -f sql/schema.sql
```

Full schema with field-level documentation is in [sql/schema.sql](sql/schema.sql).

### 3. Configure

```bash
cp .env.example .env
# Edit .env with your service URLs, Signal number, model preferences
```

### 4. Send your first URL

Via Signal: send any YouTube URL or web article link to your bot number.

Via webhook:
```bash
curl -X POST http://your-n8n:5678/webhook/signal \
  -H "Content-Type: application/json" \
  -d '{"message": "https://www.youtube.com/watch?v=example"}'
```

---

## Documentation

| Guide | What it covers |
|-------|---------------|
| [workflows/README.md](workflows/README.md) | Workflow architecture, import order, credentials, env vars |
| [sql/schema.sql](sql/schema.sql) | Full database schema with inline documentation |
| [.env.example](.env.example) | All required environment variables with descriptions |
| [docs/signal-bot-setup.md](docs/signal-bot-setup.md) | Registering and configuring signal-cli-rest-api |

---

## Roadmap

**Phase 1 (live):**
- [x] YouTube pipeline: download, transcribe, filter ads, summarize
- [x] Web pipeline: scrape, extract, clean, summarize
- [x] Signal messenger input
- [x] NextCloud file drop input
- [x] PostgreSQL job queue, content cache, deduplication
- [x] Multi-user support with access control

**Phase 1 (in progress):**
- [ ] Extended content types: GitHub repos, PDFs, X threads, podcasts
- [ ] Prompt and tag taxonomy documentation

**Phase 2 (planned):**
- [ ] Book pipeline: EPUB chapter extraction and summarization
- [ ] Translation: multilingual output via local LLM (55+ languages)

---

## Ecosystem

STMNA Signal runs on [STMNA Desk](https://github.com/stmna-io/stmna-desk): hardware selection guide, full inference stack setup, container architecture, and the systemd configuration that keeps everything running.

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

Most useful right now:
- Benchmark data on different AMD hardware configurations
- New content type pipeline implementations (PDF, GitHub, podcast)
- Bug reports with reproduction steps

---

## Acknowledgments

Built on:
- [n8n](https://n8n.io): workflow automation
- [llama.cpp](https://github.com/ggerganov/llama.cpp): local LLM inference
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp): speech recognition
- [Crawl4AI](https://github.com/unclecode/crawl4ai): web scraping
- [Obsidian](https://obsidian.md): knowledge management
- [SponsorBlock](https://sponsor.ajay.app): community-sourced ad segment data
- [Framework](https://frame.work): repairable hardware
- AMD Vulkan and ROCm ecosystem

---

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">
  <sub>Built by <a href="https://stmna.io">STMNA_</a> · Sovereign by design.</sub>
</div>
