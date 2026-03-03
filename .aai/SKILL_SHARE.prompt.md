# Share Skill - Cloudflare Pages Quick Publishing

## Goal
Publish reports, documentation, or any Markdown files with embedded images to Cloudflare Pages for instant sharing. Returns a public URL that can be opened directly from chat.

## What This Skill Does

1. Takes a document path (Markdown file with images)
2. Converts MD → HTML with proper image embedding
3. Publishes to Cloudflare Pages (free, instant)
4. Returns shareable URL for immediate viewing

## Prerequisites

### First-Time Setup (One-Time)

If Cloudflare Pages isn't set up yet, the skill will guide through setup:

1. **Cloudflare Account**
   - Free account at https://dash.cloudflare.com/sign-up
   - No credit card required

2. **Wrangler CLI**
   ```bash
   npm install -g wrangler
   # or
   npm install --save-dev wrangler
   ```

3. **Authentication**
   ```bash
   wrangler login
   # Opens browser for authentication
   ```

4. **Project Initialization**
   ```bash
   # Creates pages project (automatic on first publish)
   wrangler pages project create ai-os-reports
   ```

## Instructions

### Command: Share Document

**Usage:**
```bash
/aai-share <document-path>
```

**Examples:**
```bash
/aai-share docs/ai/reports/VALIDATION_REPORT_20260302.md
/aai-share docs/decisions/DEC-005-auth-strategy.md
/aai-share README.md
```

### Step 1: Validate Input

1. **Check Document Exists**
   ```bash
   if [ ! -f "$DOCUMENT_PATH" ]; then
     echo "ERROR: Document not found: $DOCUMENT_PATH"
     exit 1
   fi
   ```

2. **Verify File Type**
   - Must be `.md` (Markdown)
   - Or accept `.html` for direct publish

3. **Extract Document Info**
   ```bash
   DOCUMENT_DIR=$(dirname "$DOCUMENT_PATH")
   DOCUMENT_NAME=$(basename "$DOCUMENT_PATH" .md)
   ```

### Step 2: Prepare Publishing Directory

Create temporary build directory:

```bash
PUBLISH_DIR=".cloudflare-publish-$(date +%s)"
mkdir -p "$PUBLISH_DIR"
```

### Step 3: Convert Markdown to HTML

Generate standalone HTML with embedded styles and images:

```bash
# Use markdown-to-html converter
# Option 1: Using marked + highlight.js (if available)
# Option 2: Using pandoc (if available)
# Option 3: Simple conversion
```

**HTML Template:**
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{DOCUMENT_TITLE}</title>
  <style>
    /* GitHub-style Markdown CSS */
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #24292e;
      background-color: #ffffff;
      max-width: 900px;
      margin: 40px auto;
      padding: 20px;
    }

    h1, h2, h3, h4, h5, h6 {
      margin-top: 24px;
      margin-bottom: 16px;
      font-weight: 600;
      line-height: 1.25;
    }

    h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }

    code {
      background-color: rgba(27,31,35,0.05);
      border-radius: 3px;
      padding: 0.2em 0.4em;
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
      font-size: 85%;
    }

    pre {
      background-color: #f6f8fa;
      border-radius: 6px;
      padding: 16px;
      overflow: auto;
      line-height: 1.45;
    }

    pre code {
      background-color: transparent;
      padding: 0;
      font-size: 100%;
    }

    img {
      max-width: 100%;
      height: auto;
      border-radius: 6px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.12);
      margin: 20px 0;
    }

    table {
      border-collapse: collapse;
      width: 100%;
      margin: 20px 0;
    }

    table th, table td {
      border: 1px solid #dfe2e5;
      padding: 6px 13px;
    }

    table tr:nth-child(2n) {
      background-color: #f6f8fa;
    }

    blockquote {
      border-left: 4px solid #dfe2e5;
      padding: 0 15px;
      color: #6a737d;
      margin: 20px 0;
    }

    a {
      color: #0366d6;
      text-decoration: none;
    }

    a:hover {
      text-decoration: underline;
    }

    .timestamp {
      color: #6a737d;
      font-size: 0.9em;
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #eaecef;
    }
  </style>
</head>
<body>
  {MARKDOWN_CONTENT_AS_HTML}

  <div class="timestamp">
    Published: {TIMESTAMP}<br>
    Source: {DOCUMENT_PATH}
  </div>
</body>
</html>
```

### Step 4: Handle Images

**Process embedded images:**

1. **Find Image References**
   ```bash
   # Extract image paths from markdown
   grep -oP '!\[.*?\]\(\K[^)]+' "$DOCUMENT_PATH"
   ```

2. **Copy Images to Publish Directory**
   ```bash
   # For each image reference:
   # - Resolve relative path
   # - Copy to publish directory
   # - Update HTML img src to relative path

   for img in $(grep -oP '!\[.*?\]\(\K[^)]+' "$DOCUMENT_PATH"); do
     if [ -f "$DOCUMENT_DIR/$img" ]; then
       mkdir -p "$PUBLISH_DIR/$(dirname "$img")"
       cp "$DOCUMENT_DIR/$img" "$PUBLISH_DIR/$img"
     fi
   done
   ```

3. **Base64 Embed (Alternative)**
   For small images (< 100KB), optionally embed as base64:
   ```bash
   # Convert image to base64 and embed in HTML
   img_base64=$(base64 -w 0 "$img_path")
   # Replace: <img src="screenshot.png">
   # With: <img src="data:image/png;base64,$img_base64">
   ```

### Step 5: Create index.html

```bash
# Main document becomes index.html
cp "$PUBLISH_DIR/$DOCUMENT_NAME.html" "$PUBLISH_DIR/index.html"
```

### Step 6: Publish to Cloudflare Pages

```bash
# Publish using Wrangler
wrangler pages publish "$PUBLISH_DIR" \
  --project-name=ai-os-reports \
  --branch=main

# Capture output
PUBLISH_OUTPUT=$(wrangler pages publish "$PUBLISH_DIR" \
  --project-name=ai-os-reports \
  --branch=main 2>&1)

# Extract URL from output
PUBLISHED_URL=$(echo "$PUBLISH_OUTPUT" | grep -oP 'https://[^\s]+\.pages\.dev')
```

**Expected Output:**
```
🌍  Uploading... (1/3)
✨  Success! Uploaded 3 files (2.34 sec)
✅  Deployment complete!

🔗  https://ai-os-reports-abc123.pages.dev
```

### Step 7: Save Publishing Record

Store publishing metadata:

```bash
# Create publish record
mkdir -p docs/ai/published

cat > "docs/ai/published/PUBLISH_$(date +%Y%m%d_%H%M%S).jsonl" <<EOF
{"timestamp":"$(date -u +"%Y-%m-%dT%H:%M:%SZ")","document":"$DOCUMENT_PATH","url":"$PUBLISHED_URL","size_kb":$(du -k "$PUBLISH_DIR" | cut -f1)}
EOF

# Append to master log
echo '{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","action":"publish","document":"'$DOCUMENT_PATH'","url":"'$PUBLISHED_URL'"}' >> docs/ai/METRICS.jsonl
```

### Step 8: Cleanup

```bash
# Remove temporary publish directory
rm -rf "$PUBLISH_DIR"
```

### Step 9: Return Result

**Output to chat:**
```
✅ Document published successfully!

📄 Document: {DOCUMENT_NAME}
🔗 URL: {PUBLISHED_URL}

Click to open: {PUBLISHED_URL}

Details:
- Files uploaded: {FILE_COUNT}
- Total size: {SIZE_KB} KB
- Publishing time: {DURATION_SECONDS}s
- Cache: 24 hours

The URL is public and shareable. Document will remain available until manually deleted.
```

## Token Optimization

### Efficiency Strategies

1. **Template Reuse**
   - HTML template is pre-defined (no generation needed)
   - CSS styles are static

2. **Batch Processing**
   - Process all images in one pass
   - Single wrangler command for publish

3. **Caching**
   - Cloudflare auto-caches published content
   - No repeated uploads for same document

## Advanced Features

### Multi-Document Publishing

Publish entire directory:

```bash
/aai-share docs/ai/reports/
# Creates index with links to all reports
```

### Custom Styling

Override default styles via config:

```yaml
# docs/ai/publish-config.yaml
theme: github  # github, minimal, dark
custom_css: styles/custom.css
```

### Private Sharing (Protected URLs)

Add password protection:

```bash
# Use Cloudflare Access (requires setup)
wrangler pages publish "$PUBLISH_DIR" \
  --project-name=ai-os-reports \
  --branch=private-$RANDOM
```

## Integration with AI-OS Workflow

### After Validation Report

```bash
# Generate validation report with screenshots
/aai-validate-report

# Immediately share for review
/aai-share docs/ai/reports/VALIDATION_REPORT_20260302T100000Z.md

# Returns: https://ai-os-reports-xyz.pages.dev
```

### Share Decision Artifacts

```bash
# After making decision
# Decision saved to: docs/decisions/DEC-008-database-choice.md

# Share with team
/aai-share docs/decisions/DEC-008-database-choice.md
```

### TDD Evidence Sharing

```bash
# After TDD cycle completion
/aai-tdd
# ... RED-GREEN-REFACTOR ...

# Share TDD evidence
/aai-share-tdd-report
# Auto-generates HTML report with all evidence logs
# Publishes to Cloudflare
```

## Troubleshooting

### Wrangler not found
```bash
npm install -g wrangler
# or add to project
npm install --save-dev wrangler
```

### Authentication failed
```bash
wrangler logout
wrangler login
# Re-authenticate
```

### Image not displaying
- Check image path is relative to document
- Verify image file exists
- Try base64 embedding for small images

### Publish failed
```bash
# Check Cloudflare status
wrangler pages deployment list --project-name=ai-os-reports

# Retry publish
wrangler pages publish "$PUBLISH_DIR" --project-name=ai-os-reports
```

### URL not returned
- Check wrangler output format
- Look for URL in: https://dash.cloudflare.com/pages

## Metrics

Track publishing activity in `docs/ai/METRICS.jsonl`:

```jsonl
{"timestamp":"2026-03-02T19:30:00Z","type":"publish","document":"docs/ai/reports/VALIDATION_REPORT.md","url":"https://ai-os-reports-abc.pages.dev","size_kb":245,"duration_seconds":3.2}
```

## Security & Privacy

**Public by Default:**
- All published documents are PUBLIC
- Anyone with URL can access
- No expiration (until manually deleted)

**Best Practices:**
- Don't publish sensitive data (credentials, keys)
- Redact personal information
- Use private branches for confidential reports

**Cleanup:**
```bash
# Delete old deployments
wrangler pages deployment list --project-name=ai-os-reports
wrangler pages deployment delete <deployment-id>
```

## Cost

**Cloudflare Pages Free Tier:**
- Unlimited sites
- Unlimited requests
- 500 builds/month
- 20,000 files per deployment
- Perfect for AI-OS reports

**Paid Plan ($20/mo):**
- Only if you need more builds
- Not required for typical use

## Example Complete Flow

```bash
# 1. Generate validation report (with screenshots)
/aai-validate-report

# Output:
# ✅ Report generated: docs/ai/reports/VALIDATION_REPORT_20260302T120000Z.md
# Screenshots: 3 files

# 2. Share report
/aai-share docs/ai/reports/VALIDATION_REPORT_20260302T120000Z.md

# Processing...
# Converting MD → HTML...
# Embedding 3 images...
# Publishing to Cloudflare...

# Output:
# ✅ Document published successfully!
# 🔗 URL: https://ai-os-reports-a1b2c3.pages.dev
# Click to open: https://ai-os-reports-a1b2c3.pages.dev

# 3. Open in browser (from chat)
# User clicks URL → Report opens with all images
```

## Future Enhancements

1. **Automatic Sharing**
   - Auto-publish reports after validation
   - Configurable via STATE.yaml

2. **Custom Domains**
   - Map to your domain: reports.mycompany.com
   - Via Cloudflare DNS

3. **Version History**
   - Keep previous versions
   - Compare report versions side-by-side

4. **Collaboration**
   - Comment on published reports
   - Via Cloudflare Workers + KV storage
