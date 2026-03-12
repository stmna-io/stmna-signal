# STMNA Signal — Custom n8n Image
# Extends official n8n with: ffmpeg (for audio processing), yt-dlp (YouTube download)
#
# TODO: Flesh out in SB-06 (Staging Pipeline session)
# This Dockerfile is a placeholder showing the intended structure.
# Final version will be tested against a clean staging VM.

FROM n8nio/n8n:latest

# Switch to root for system package installs
USER root

# TODO: Install ffmpeg and yt-dlp (Alpine-compatible)
# RUN apk add --no-cache ffmpeg python3 py3-pip && \
#     pip3 install yt-dlp && \
#     apk del py3-pip

# Revert to n8n default user
USER node

# Labels
LABEL org.opencontainers.image.source="https://github.com/stmna-io/stmna-signal"
LABEL org.opencontainers.image.description="STMNA Signal n8n image with ffmpeg + yt-dlp"
LABEL org.opencontainers.image.licenses="Apache-2.0"
