#!/usr/bin/env bash
set -euo pipefail

# Cloudflare Pages Quick Share Script
# Usage: ./scripts/cloudflare-share.sh <document.md>

DOCUMENT_PATH="${1:-}"
if [[ -z "$DOCUMENT_PATH" ]]; then
  echo "Usage: $0 <document.md>"
  echo "Example: $0 docs/ai/reports/VALIDATION_REPORT.md"
  exit 1
fi

if [[ ! -f "$DOCUMENT_PATH" ]]; then
  echo "ERROR: Document not found: $DOCUMENT_PATH"
  exit 1
fi

# Extract document info
DOCUMENT_DIR=$(dirname "$DOCUMENT_PATH")
DOCUMENT_NAME=$(basename "$DOCUMENT_PATH" .md)
DOCUMENT_TITLE="$DOCUMENT_NAME"

# Create temporary publish directory
PUBLISH_DIR=".cloudflare-publish-$(date +%s)"
mkdir -p "$PUBLISH_DIR"

echo "📦 Preparing document for publishing..."

# Convert Markdown to HTML
cat > "$PUBLISH_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DOCUMENT_TITLE_PLACEHOLDER</title>
  <style>
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
CONTENT_PLACEHOLDER
  <div class="timestamp">
    Published: TIMESTAMP_PLACEHOLDER<br>
    Source: SOURCE_PATH_PLACEHOLDER
  </div>
</body>
</html>
EOF

# Check for markdown converter
if command -v pandoc >/dev/null 2>&1; then
  echo "📝 Converting with pandoc..."
  CONTENT=$(pandoc -f markdown -t html "$DOCUMENT_PATH")
elif command -v marked >/dev/null 2>&1; then
  echo "📝 Converting with marked..."
  CONTENT=$(marked "$DOCUMENT_PATH")
else
  echo "⚠️  No markdown converter found (pandoc/marked)"
  echo "📝 Using basic conversion..."
  # Basic markdown to HTML (limited)
  CONTENT=$(<"$DOCUMENT_PATH")
  # Convert headers
  CONTENT=$(echo "$CONTENT" | sed -E 's/^# (.+)$/<h1>\1<\/h1>/')
  CONTENT=$(echo "$CONTENT" | sed -E 's/^## (.+)$/<h2>\1<\/h2>/')
  CONTENT=$(echo "$CONTENT" | sed -E 's/^### (.+)$/<h3>\1<\/h3>/')
  # Convert paragraphs
  CONTENT=$(echo "$CONTENT" | sed -E 's/^(.+)$/<p>\1<\/p>/')
fi

# Replace placeholders
sed -i "s|DOCUMENT_TITLE_PLACEHOLDER|$DOCUMENT_TITLE|g" "$PUBLISH_DIR/index.html"
sed -i "s|TIMESTAMP_PLACEHOLDER|$(date -u +"%Y-%m-%d %H:%M:%S UTC")|g" "$PUBLISH_DIR/index.html"
sed -i "s|SOURCE_PATH_PLACEHOLDER|$DOCUMENT_PATH|g" "$PUBLISH_DIR/index.html"
sed -i "s|CONTENT_PLACEHOLDER|$CONTENT|g" "$PUBLISH_DIR/index.html"

# Copy images
echo "🖼️  Processing images..."
IMAGE_COUNT=0
while IFS= read -r img_ref; do
  # Extract image path from markdown ![alt](path)
  img_path=$(echo "$img_ref" | grep -oP '!\[.*?\]\(\K[^)]+' || true)
  if [[ -n "$img_path" && -f "$DOCUMENT_DIR/$img_path" ]]; then
    mkdir -p "$PUBLISH_DIR/$(dirname "$img_path")"
    cp "$DOCUMENT_DIR/$img_path" "$PUBLISH_DIR/$img_path"
    ((IMAGE_COUNT++))
  fi
done < <(grep -o '!\[.*\](.*)' "$DOCUMENT_PATH" || true)

echo "   Found $IMAGE_COUNT images"

# Check for wrangler
if ! command -v wrangler >/dev/null 2>&1; then
  echo "❌ ERROR: wrangler not found"
  echo "Install: npm install -g wrangler"
  echo "Then run: wrangler login"
  rm -rf "$PUBLISH_DIR"
  exit 1
fi

# Publish to Cloudflare Pages
echo "🚀 Publishing to Cloudflare Pages..."
PROJECT_NAME="ai-os-reports"

PUBLISH_OUTPUT=$(wrangler pages publish "$PUBLISH_DIR" \
  --project-name="$PROJECT_NAME" \
  --branch=main 2>&1 || true)

# Extract URL
PUBLISHED_URL=$(echo "$PUBLISH_OUTPUT" | grep -oP 'https://[^\s]+\.pages\.dev' | head -1)

if [[ -z "$PUBLISHED_URL" ]]; then
  echo "❌ Publishing failed or URL not found"
  echo "$PUBLISH_OUTPUT"
  rm -rf "$PUBLISH_DIR"
  exit 1
fi

# Calculate size
SIZE_KB=$(du -sk "$PUBLISH_DIR" | cut -f1)

# Cleanup
rm -rf "$PUBLISH_DIR"

# Save publishing record
mkdir -p docs/ai/published
echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"document\":\"$DOCUMENT_PATH\",\"url\":\"$PUBLISHED_URL\",\"size_kb\":$SIZE_KB}" >> docs/ai/published/history.jsonl

# Output success
echo ""
echo "✅ Document published successfully!"
echo ""
echo "📄 Document: $DOCUMENT_NAME"
echo "🔗 URL: $PUBLISHED_URL"
echo ""
echo "Click to open: $PUBLISHED_URL"
echo ""
echo "Details:"
echo "- Images: $IMAGE_COUNT"
echo "- Size: ${SIZE_KB} KB"
echo ""
