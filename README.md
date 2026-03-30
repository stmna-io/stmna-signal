<div align="center">

  <h1>STMNA_Signal</h1>
  <h3>Content Intelligence Pipeline</h3>
  <p><em>Send any URL. Get back a structured knowledge note. Everything runs on your hardware.</em></p>

  [![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
  ![Status](https://img.shields.io/badge/Status-Coming%20Soon-yellow)

</div>

---

STMNA_Signal processes YouTube videos, web articles, ebooks, and voice notes into structured knowledge notes. Send a URL via Signal messenger, webhook, or Nextcloud. Get back a summary with optional translation and TTS audio. Four n8n workflows, fully open source.

## What It Does

📺 **YouTube → Structured Notes**  Send a YouTube URL via Signal messenger or Nextcloud. Get back a structured summary with key points, timestamps, and optional translation.

🌐 **Web Articles → Key Points**  Send any URL. Get extracted content, summarized and formatted as a knowledge note in your vault.

📚 **Ebooks → Chapter Summaries**  Drop an EPUB or PDF into Nextcloud. Get chapter-by-chapter summaries with optional translation to your preferred language.

🔊 **Audio Summaries**  Any processed content can be converted to a voice memo via text-to-speech, ready to listen on the go.

## How It Works

Four n8n workflows handle content type detection, extraction, LLM processing, and output routing. Everything runs locally on your STMNA_Desk.

## Requirements

- [STMNA_Desk](https://github.com/stmna-io/stmna-desk) with the full stack running (inference, n8n, PostgreSQL, Nextcloud)
- Signal messenger account (for the Signal input path)

## Ecosystem

| Product | Description | Repo |
|---------|-------------|------|
| **STMNA_Desk** | Self-hosted AI inference stack (reference architecture for AMD hardware) | [stmna-desk](https://github.com/stmna-io/stmna-desk) |
| **STMNA_Voice** | Self-improving push-to-talk speech-to-text pipeline | [stmna-voice](https://github.com/stmna-io/stmna-voice) |
| **STMNA_Voice Mobile** | Sovereign push-to-talk voice input for Android | [stmna-voice-mobile](https://github.com/stmna-io/stmna-voice-mobile) |

---

<div align="center">
  <sub>Built by <a href="https://github.com/stmna-io">STMNA_</a> · Engineered resilience. Sovereign by design.</sub>
</div>
