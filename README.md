
<div align="center">
  <!-- TODO: Replace with actual banner -->
  <!-- Banner: Deep Navy (#1A1A2E) background, Ember Orange (#FF8C42) accents -->
  <!-- STMNA pixel S logo + Signal wordmark -->
  
  <h1>STMNA Signal</h1>
  <h3>Universal Content Intelligence Pipeline</h3>
  <p><em>Share any URL — get structured intelligence back. 100% sovereign, zero cloud.</em></p>

  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
  [![Built on AMD](https://img.shields.io/badge/Built%20on-AMD%20Strix%20Halo-ED1C24)](https://www.amd.com)
  [![Powered by n8n](https://img.shields.io/badge/Powered%20by-n8n-FF6D5A)](https://n8n.io)
  [![Framework Desktop](https://img.shields.io/badge/Hardware-Framework%20Desktop-000000)](https://frame.work)
  ![Status](https://img.shields.io/badge/Status-Phase%201A%20Deployed-brightgreen)
  
  <br/>
  
  [📖 Documentation](#documentation) · [🚀 Quick Start](#quick-start) · [🏗️ Architecture](#architecture) · [📊 Benchmarks](#benchmarks) · [🤝 Contributing](#contributing)
</div>

---

<!-- TODO: Hero GIF: 15-20 second demo of sending a YouTube URL via Signal → receiving summary -->
<div align="center">
  <!-- <img src="assets/demo.gif" alt="STMNA Signal Demo" width="700"/> -->
  <em>Send a YouTube URL via Signal → receive a structured intelligence note in your vault in under 2 minutes</em>
</div>

---

## ⚡ What is STMNA Signal?

STMNA Signal is a **self-hosted content intelligence pipeline** that turns any URL into structured, searchable knowledge. YouTube videos, web articles, GitHub repos, PDFs, podcasts — share it via Signal messenger, webhook, or file drop, and receive an AI-summarized intelligence note in your personal knowledge vault.

**No cloud APIs. No data leaves your machine. Built entirely on AMD consumer hardware.**

### Why?

We consume 30+ pieces of content daily but retain almost nothing. STMNA Signal solves the "I watched a great video but can't remember what it said" problem by:

- **Processing content you can't consume raw** — a 2h30m video becomes a 3-minute read
- **Preserving it permanently** in a structured knowledge system (Obsidian vault)
- **Running entirely on your own hardware** — your browsing habits, summaries, and knowledge base never touch a third-party server

### Hardware Requirement

STMNA Signal runs on [STMNA Desk](https://github.com/stmna-io/stmna-desk) — a sovereign AI workstation stack built on AMD Strix Halo. See the Desk repo for hardware guide and full stack setup.

---

## 🎯 Key Features

| Feature | Description |
|---|---|
| 📱 **Signal-first** | Share from any app on your phone — the pipeline catches it |
| 🎬 **YouTube Pipeline** | Download → transcribe (whisper.cpp) → filter ads (SponsorBlock) → summarize (Qwen) |
| 🌐 **Web Pipeline** | Crawl4AI scrape → clean → summarize → full article preserved |
| ⚡ **Real Performance** | 3.5min video = 25s · 42min = 118s · 2h29min = 284s end-to-end |
| 🔒 **100% Sovereign** | Every byte stays on your hardware. Zero cloud, zero telemetry |
| 🏷️ **Smart Tagging** | Controlled taxonomy + discovery tags, auto-classified |
| 🗂️ **Obsidian Native** | Notes with rich YAML frontmatter, ready for Dataview queries |
| 🔄 **n8n Orchestrated** | Visual workflow automation — modify without code |
| 💻 **AMD Native** | Vulkan (llama.cpp, whisper.cpp) + ROCm — no CUDA needed |

---

## 📊 Benchmarks

Measured on AMD Ryzen AI Max+ 395 (Strix Halo) · 128GB unified · Radeon 8060S (gfx1151)

| Content | Duration | End-to-End | Model |
|---|---|---|---|
| Short YouTube | 3.5 min | **25 seconds** | whisper large-v3-turbo Q5 + Qwen3-30B |
| Medium YouTube | 42 min | **118 seconds** | whisper large-v3-turbo Q5 + Qwen3-30B |
| Long YouTube | 2h 29min | **284 seconds** | whisper large-v3-turbo Q5 + Qwen3-30B |
| Web article | any | **< 30 seconds** | Crawl4AI + Qwen3-30B |
| Cache hit | any | **< 1 second** | Served from PostgreSQL |

---

## 🏗️ Architecture

```
📱 Signal / 🌐 Webhook / 📁 NextCloud / 📧 Email
                    │
                    ▼
        ┌─── Command Parser ───┐
        │  flags: quick, deep, │
        │  tts, translate, dub │
        └──────────┬───────────┘
                   ▼
           Content Router
        ┌──────┼──────┐
        ▼      ▼      ▼
    YouTube   Web   GitHub   ... (PDF, X, Podcast, Book)
        │      │      │
        ▼      ▼      ▼
   ┌─────────────────────┐
   │  Stage 1: Qwen      │  ← Fast, local, real-time
   │  Factual summary    │
   └──────────┬──────────┘
              ▼
   ┌─────────────────────┐
   │  Obsidian Vault     │  ← Structured notes + frontmatter
   │  (30-SIGNALS/)      │
   └──────────┬──────────┘
              ▼
   ┌─────────────────────┐
   │  Stage 2: Claude    │  ← Strategic analysis, daily brief
   │  (daily/weekly)     │     Full project context
   └─────────────────────┘
```

### The Tech Stack

| Component | Technology | Role |
|---|---|---|
| **Orchestration** | n8n (self-hosted) | Visual workflow automation |
| **LLM Inference** | llama-swap → Qwen3-30B-Instruct | Summarization, classification |
| **Transcription** | whisper.cpp (Vulkan) | Speech-to-text, large-v3-turbo |
| **Web Scraping** | Crawl4AI | Article extraction |
| **Ad Filtering** | SponsorBlock API + Qwen prompt | Two-layer ad removal |
| **Messaging** | signal-cli-rest-api | Mobile-first entry point |
| **Knowledge Base** | Obsidian | Markdown vault with YAML frontmatter |
| **Cache/DB** | PostgreSQL + PGVector | Deduplication, embeddings |
| **Translation** | TranslateGemma 27B | 55-language translation (Phase 2) |
| **TTS** | Dia 1.6B / F5-TTS | Voice synthesis (Phase 2) |
| **Hardware** | [STMNA Desk](https://github.com/stmna-io/stmna-desk) | AMD Strix Halo + Framework Desktop |

### Why AMD Native (Not CUDA)

We deliberately chose AMD-native tooling over CUDA-dependent alternatives. When evaluating WhisperX (the standard choice for transcription), we discovered it was fundamentally CUDA-dependent on gfx1151. Rather than forcing compatibility layers, we pivoted to **whisper.cpp** (Vulkan) — which runs natively and outperforms our targets.

This validates AMD's ecosystem for real AI workloads: Vulkan for inference (llama.cpp, whisper.cpp), ROCm for PyTorch-dependent ML (TTS), all on the same chip.

> Read the full story: [Choosing AMD-Native Tooling for a Sovereign AI Pipeline](#) *(blog post — coming soon)*

---

## 🚀 Quick Start

### Prerequisites

- [STMNA Desk](https://github.com/stmna-io/stmna-desk) stack running (or equivalent: AMD GPU + Vulkan + llama-swap + whisper.cpp + n8n)
- Signal number registered with signal-cli-rest-api (optional — webhook works without it)
- Obsidian vault (or any markdown-based knowledge system)

### 1. Clone

```bash
git clone https://github.com/stmna-io/stmna-signal.git
cd stmna-signal
```

### 2. Deploy Services

```bash
# Start Signal-specific services (assumes Desk stack is running)
docker compose up -d

# Import n8n workflows
./scripts/import-workflows.sh
```

### 3. Configure

```bash
cp .env.example .env
# Edit .env with your Signal number, vault path, model preferences
```

### 4. Send Your First URL

```
# Via Signal: just send a YouTube URL to your bot number
https://www.youtube.com/watch?v=dQw4w9WgXcQ

# Via webhook:
curl -X POST http://localhost:5678/webhook/signal \
  -H "Content-Type: application/json" \
  -d '{"message": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}'
```

📖 **[Full Setup Guide →](docs/setup.md)**

---

## 📋 Roadmap

- [x] **Phase 1A** — YouTube + Web pipelines via Signal ✅
- [ ] **Phase 1B** — Templates, prompts & tag taxonomy
- [ ] **Phase 1C** — Pipeline queue, cache & multi-user
- [ ] **Phase 1D** — Extended content types (X, GitHub, PDF, images, voice notes)
- [ ] **Phase 1E** — NextCloud file ingestion
- [ ] **Phase 2A** — Book digest pipeline (EPUB → chapter summaries)
- [ ] **Phase 2B** — Translation (TranslateGemma 27B, 55 languages)
- [ ] **Phase 2C** — EPUB translation
- [ ] **Phase 2D** — Text-to-speech (Dia + F5-TTS)
- [ ] **Phase 2E** — AI dubbing with voice cloning

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Areas where help is appreciated:
- 📝 Documentation improvements
- 🐛 Bug reports and fixes
- 🔧 New content type pipelines
- 🌍 Translation of documentation
- 📊 Benchmark data on different AMD hardware

---

## 📄 License

MIT License — see [LICENSE](LICENSE)

---

## 🙏 Acknowledgments

Built with and inspired by:
- [n8n](https://n8n.io) — Workflow automation
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — LLM inference
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — Speech recognition
- [Crawl4AI](https://github.com/unclecode/crawl4ai) — Web scraping
- [Obsidian](https://obsidian.md) — Knowledge management
- [SponsorBlock](https://sponsor.ajay.app) — Community ad filtering
- [Framework](https://frame.work) — Repairable hardware
- AMD ROCm & Vulkan ecosystem

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://stmna.io">STMNA_</a> · Engineered resilience. Sovereign by design.</sub>
</div>
