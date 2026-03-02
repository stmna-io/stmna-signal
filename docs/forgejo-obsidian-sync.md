# Forgejo + Obsidian Sync

<!-- TODO: Write full Forgejo/Obsidian sync guide for SB-07 session -->
<!-- Content: how processed Signal notes land in git repo on Forgejo,
     Obsidian Git plugin config for auto-pull, vault structure (30-SIGNALS/ folder),
     note format (YAML frontmatter, tags, content structure),
     multi-user setup (how each user gets their own Signal number + vault branch) -->

## Placeholder

This document will cover:

### Output: Where Notes Land

- Vault path: `30-SIGNALS/` subdirectory structure
- YAML frontmatter format (title, source, tags, created, processed_at)
- Note naming convention: `YYYY-MM-DD-slug.md`
- Tag taxonomy: controlled tags + discovery tags

### Forgejo Integration

- n8n writes notes directly to vault via git operations
- Commit format: `signal: [content-type] [title]`
- Forgejo webhook → Obsidian Git plugin auto-pull

### Obsidian Git Plugin

- Install and configure Obsidian Git on your Obsidian instance
- Auto-pull interval: 5 minutes recommended
- Conflict resolution strategy

### Multi-User Setup

- Each user gets a Signal phone number registered to signal-cli
- User-specific vault branches or subdirectories
- Shared pipeline, isolated outputs

Coming in SB-07 session.
