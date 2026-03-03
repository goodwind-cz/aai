# Share Skill — Publish to Cloudflare Pages

## Goal
Convert a Markdown document to HTML and publish it to Cloudflare Pages. Returns a public URL.

## Prerequisites (one-time)

```bash
npm install -g wrangler
wrangler login
wrangler pages project create aai-reports   # auto-creates on first deploy
```

## Instructions

When the user runs `/aai-share <document-path>`:

### 1. Validate
- Confirm the file exists and is `.md`
- If not found, report the error and stop

### 2. Convert
```bash
mkdir -p .cloudflare-publish
node .aai/scripts/share-convert.mjs <document-path> .cloudflare-publish
```
This converts Markdown → `index.html` with GitHub-style CSS and copies referenced images.

### 3. Deploy
```bash
wrangler pages deploy .cloudflare-publish --project-name=aai-reports --branch=main
```
Extract the `https://....pages.dev` URL from the output.

### 4. Record
```bash
mkdir -p docs/ai/published
echo '{"timestamp":"<ISO>","document":"<path>","url":"<url>"}' >> docs/ai/published/history.jsonl
```

### 5. Cleanup
```bash
rm -rf .cloudflare-publish
```

### 6. Report
```
Document published successfully!

Document: <name>
URL: <url>

Click to open: <url>
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `wrangler: not found` | `npm install -g wrangler` |
| Auth failed | `wrangler logout && wrangler login` |
| Images missing | Check paths are relative to the document |
| Deploy fails | `wrangler pages deployment list --project-name=aai-reports` |

## Security
All published documents are **public**. Do not publish credentials, secrets, or personal data.

## Scripts
Shell scripts for non-agent use: `.aai/scripts/cloudflare-share.sh` (bash) and `.aai/scripts/cloudflare-share.ps1` (PowerShell).
