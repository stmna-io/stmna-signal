## Pre-Push Sanitization (MANDATORY)

This section applies to EVERY commit on this repo. Read it. Follow it. No exceptions.

### Never commit any of the following:

**Personal infrastructure data:**
- Real IP addresses (LAN, Tailscale, or any specific IP)
- Real domain names (replace with `yourdomain.com` or `YOUR_DOMAIN`)
- Phone numbers, real email addresses, real names of non-public individuals
- File paths containing real usernames (e.g. `/home/stmna/`, `/data/second-brain/`)
- Real UUIDs from production systems
- Bearer tokens, API keys, passwords, database connection strings, encryption keys
- n8n credential IDs or credential names that reveal infrastructure details
- Forgejo/Gitea internal URLs

**AI tool traces:**
- References to Claude Code, Claude, Anthropic, or any AI coding assistant
- Comments, commit messages, or documentation that mention AI-assisted development
- Code comments that sound AI-generated (verbose, over-explanatory, perfectly structured paragraphs)
- Em dashes in any text content

**Process artifacts:**
- References to internal vault notes, decision logs, or sprint documents
- Commit messages that reference sanitization, cleanup, or removal of personal data
- References to specific session briefs or build log entries

### n8n workflow JSON rules:

All workflow JSONs must be sanitized before commit:
- Strip: `id`, `createdAt`, `updatedAt`, `versionId`, `usedCredentials`, `meta.instanceId`, `homeProject`, `scopes`
- Replace all credential IDs and names with `YOUR_CREDENTIAL_*` placeholders
- Replace all IP addresses, domains, phone numbers, file paths, UUIDs with `YOUR_*` placeholders
- Set `active` to `false`

### Code node comment style:

All comments in n8n Code nodes and any script files must read like a senior developer wrote them:
- Terse, practical, direct
- "Why" comments, not "what" comments
- No preambles: never start with "This section...", "We then proceed to...", "First, we need to..."
- Vary density: obvious code gets no comment, tricky logic gets real explanation
- Never use em dashes
- Write like you're leaving notes for a teammate, not writing documentation for a stranger

### Pre-push verification command:

Run this before EVERY push. It must return zero results.

```bash
echo "=== Personal data check ==="
grep -rn 'slowdawn\|10\.0\.10\.\|100\.64\.\|/home/stmna\|/data/second-brain' --include='*.md' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.py' --include='*.sql' .

echo "=== AI tool traces ==="
grep -rni 'claude code\|anthropic\|AI-generated\|AI-assisted\|built with claude\|built by claude' --include='*.md' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.py' .

echo "=== Credential patterns ==="
grep -rn 'Bearer [A-Za-z0-9]\|postgres://[a-z]' --include='*.md' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.sh' .
```

If ANY line returns a real value (not a placeholder), fix it before pushing.
