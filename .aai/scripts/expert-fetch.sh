#!/usr/bin/env bash
# expert-fetch.sh — Fetch and cache expert subagent prompts from VoltAgent registry
# Usage: expert-fetch.sh <expert-key> [--force]
#
# Returns: path to cached expert prompt file on stdout
# Exit codes: 0=success, 1=rejected/error, 2=not found in registry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="$REPO_ROOT/.aai/system/EXPERT_REGISTRY.yaml"
CACHE_DIR="$REPO_ROOT/.aai/cache/experts"

EXPERT_KEY="${1:-}"
FORCE="${2:-}"

if [ -z "$EXPERT_KEY" ]; then
  echo "Usage: expert-fetch.sh <expert-key> [--force]" >&2
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Registry not found at $REGISTRY" >&2
  exit 1
fi

# Parse registry values
PINNED_SHA=$(grep 'pinned_sha:' "$REGISTRY" | head -1 | sed 's/.*"\(.*\)".*/\1/')
MAX_BYTES=$(grep 'max_prompt_bytes:' "$REGISTRY" | head -1 | awk '{print $2}')
REPO_NAME=$(grep 'repo:' "$REGISTRY" | head -1 | awk '{print $2}')
BASE_PATH=$(grep 'base_path:' "$REGISTRY" | head -1 | awk '{print $2}')

if [ -z "$PINNED_SHA" ] || [ -z "$REPO_NAME" ]; then
  echo "ERROR: Invalid registry — missing pinned_sha or repo" >&2
  exit 1
fi

# Find expert path in registry
# Look for "  <key>:" then grab the next "path:" value
EXPERT_PATH=$(awk "/^  ${EXPERT_KEY}:/{found=1; next} found && /path:/{print \$2; exit}" "$REGISTRY")

if [ -z "$EXPERT_PATH" ]; then
  echo "ERROR: Expert '$EXPERT_KEY' not found in registry" >&2
  exit 2
fi

# Check blocked categories
CATEGORY=$(echo "$EXPERT_PATH" | cut -d'/' -f1)
if grep -q "  - $CATEGORY" <<< "$(awk '/^blocked_categories:/,/^[a-z]/' "$REGISTRY")"; then
  echo "ERROR: Category '$CATEGORY' is blocked in registry" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"

CACHE_FILE="$CACHE_DIR/${EXPERT_KEY}.md"
SHA_FILE="$CACHE_DIR/.sha_${EXPERT_KEY}"

# Cache check (skip if --force)
if [ "$FORCE" != "--force" ] && [ -f "$CACHE_FILE" ] && [ -f "$SHA_FILE" ]; then
  CACHED_SHA=$(cat "$SHA_FILE")
  if [ "$CACHED_SHA" = "$PINNED_SHA" ]; then
    echo "$CACHE_FILE"
    exit 0
  fi
fi

# Fetch from pinned SHA
FULL_PATH="${BASE_PATH}/${EXPERT_PATH}"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if ! gh api "repos/${REPO_NAME}/contents/${FULL_PATH}?ref=${PINNED_SHA}" \
  --jq '.content' 2>/dev/null | base64 -d > "$TMPFILE" 2>/dev/null; then
  echo "ERROR: Failed to fetch $FULL_PATH at SHA $PINNED_SHA" >&2
  exit 1
fi

# Size check
FILE_SIZE=$(wc -c < "$TMPFILE")
if [ "$FILE_SIZE" -gt "$MAX_BYTES" ]; then
  echo "REJECTED: Expert prompt too large (${FILE_SIZE} > ${MAX_BYTES} bytes)" >&2
  exit 1
fi

# Content sanitization — reject prompt injection patterns
if grep -qiE '(ignore.*previous|disregard.*instruction|you are now|forget.*above|override.*system)' "$TMPFILE"; then
  echo "REJECTED: Expert prompt contains injection patterns" >&2
  exit 1
fi

# Strip dangerous command patterns from body (after frontmatter)
# We keep the file but neutralize destructive instructions
sed -i \
  -e '/git push/d' \
  -e '/git reset --hard/d' \
  -e '/rm -rf/d' \
  -e '/force.push/d' \
  -e '/--no-verify/d' \
  "$TMPFILE"

# Write to cache
mv "$TMPFILE" "$CACHE_FILE"
echo "$PINNED_SHA" > "$SHA_FILE"
trap - EXIT

echo "$CACHE_FILE"
