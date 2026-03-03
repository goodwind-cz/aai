#!/usr/bin/env bash
set -euo pipefail

# Cloudflare Pages Quick Share Script
# Usage: ./cloudflare-share.sh <document.md>

DOCUMENT_PATH="${1:-}"
if [[ -z "$DOCUMENT_PATH" ]]; then
  echo "Usage: $0 <document.md>"
  exit 1
fi

if [[ ! -f "$DOCUMENT_PATH" ]]; then
  echo "ERROR: Document not found: $DOCUMENT_PATH"
  exit 1
fi

DOCUMENT_NAME=$(basename "$DOCUMENT_PATH" .md)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLISH_DIR=".cloudflare-publish"

# Ensure clean publish dir
rm -rf "$PUBLISH_DIR"
mkdir -p "$PUBLISH_DIR"

echo "Converting Markdown to HTML..."
node "$SCRIPT_DIR/share-convert.mjs" "$DOCUMENT_PATH" "$PUBLISH_DIR"

# Check for wrangler
if ! command -v wrangler >/dev/null 2>&1; then
  echo "ERROR: wrangler not found"
  echo "Install: npm install -g wrangler"
  echo "Then run: wrangler login"
  rm -rf "$PUBLISH_DIR"
  exit 1
fi

# Derive branch name from git repo name (isolates projects in CF Pages)
BRANCH_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || basename "$PWD")
BRANCH_NAME=$(echo "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

# Deploy to Cloudflare Pages
echo "Deploying to Cloudflare Pages (branch: $BRANCH_NAME)..."
PROJECT_NAME="aai-reports"

DEPLOY_OUTPUT=$(wrangler pages deploy "$PUBLISH_DIR" \
  --project-name="$PROJECT_NAME" \
  --branch="$BRANCH_NAME" 2>&1 || true)

# Extract URL
PUBLISHED_URL=$(echo "$DEPLOY_OUTPUT" | grep -oP 'https://[^\s]+\.pages\.dev' | head -1)

if [[ -z "$PUBLISHED_URL" ]]; then
  echo "Deployment failed or URL not found"
  echo "$DEPLOY_OUTPUT"
  rm -rf "$PUBLISH_DIR"
  exit 1
fi

SIZE_KB=$(du -sk "$PUBLISH_DIR" | cut -f1)

# Cleanup
rm -rf "$PUBLISH_DIR"

# Save publishing record
mkdir -p docs/ai/published
echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"document\":\"$DOCUMENT_PATH\",\"url\":\"$PUBLISHED_URL\",\"size_kb\":$SIZE_KB}" >> docs/ai/published/history.jsonl

echo ""
echo "Document published successfully!"
echo ""
echo "Document: $DOCUMENT_NAME"
echo "URL: $PUBLISHED_URL"
echo ""
echo "Click to open: $PUBLISHED_URL"
echo ""
