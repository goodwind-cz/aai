#!/usr/bin/env bash
# expert-fetch.sh — Fetch and cache expert subagent prompts from VoltAgent registry
#
# Usage:
#   expert-fetch.sh <expert-key>           Fetch expert by registry key
#   expert-fetch.sh <expert-key> --force   Fetch ignoring cache
#   expert-fetch.sh --detect <ext|tech>... Auto-detect experts from extensions/keywords
#   expert-fetch.sh --body <expert-key>    Print just the prompt body (no frontmatter)
#   expert-fetch.sh --list                 List all available expert keys (one per line)
#   expert-fetch.sh --check <expert-key> <phase>  Check if expert is eligible for phase
#
# Returns: path to cached expert prompt file on stdout (fetch/detect modes)
# Exit codes: 0=success, 1=rejected/error, 2=not found in registry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="$REPO_ROOT/.aai/system/EXPERT_REGISTRY.yaml"
CACHE_DIR="$REPO_ROOT/.aai/cache/experts"

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Registry not found at $REGISTRY" >&2
  exit 1
fi

# ── --list: dump all expert keys (one per line, ~100 bytes total) ──
if [ "${1:-}" = "--list" ]; then
  awk '/^  [a-z][a-z0-9_-]*:$/{gsub(/[: ]/,""); print}' "$REGISTRY"
  exit 0
fi

# ── --detect: map file extensions / tech keywords → expert keys ──
if [ "${1:-}" = "--detect" ]; then
  shift
  MATCHES=""
  for TOKEN in "$@"; do
    # Normalize: strip dots, lowercase
    TOKEN=$(echo "$TOKEN" | tr '[:upper:]' '[:lower:]' | sed 's/^\.//')
    case "$TOKEN" in
      ts|tsx|typescript)   MATCHES="$MATCHES typescript" ;;
      js|jsx|javascript)   MATCHES="$MATCHES javascript" ;;
      py|python)           MATCHES="$MATCHES python" ;;
      rb|ruby|rails)       MATCHES="$MATCHES rails" ;;
      rs|rust)             MATCHES="$MATCHES rust" ;;
      go|golang)           MATCHES="$MATCHES golang" ;;
      java)                MATCHES="$MATCHES java" ;;
      cs|csharp)           MATCHES="$MATCHES csharp" ;;
      swift)               MATCHES="$MATCHES swift" ;;
      kt|kotlin)           MATCHES="$MATCHES kotlin" ;;
      dart|flutter)        MATCHES="$MATCHES flutter" ;;
      php)                 MATCHES="$MATCHES php" ;;
      ex|exs|elixir)       MATCHES="$MATCHES elixir" ;;
      cpp|cc|cxx|hpp|c++)  MATCHES="$MATCHES cpp" ;;
      sql|psql)            MATCHES="$MATCHES sql" ;;
      ps1|powershell)      MATCHES="$MATCHES powershell" ;;
      graphql|gql)         MATCHES="$MATCHES graphql" ;;
      vue)                 MATCHES="$MATCHES vue" ;;
      react|jsx)           MATCHES="$MATCHES react" ;;
      angular)             MATCHES="$MATCHES angular" ;;
      next|nextjs)         MATCHES="$MATCHES nextjs" ;;
      django)              MATCHES="$MATCHES django" ;;
      laravel)             MATCHES="$MATCHES laravel" ;;
      spring)              MATCHES="$MATCHES spring" ;;
      dotnet|.net)         MATCHES="$MATCHES dotnet" ;;
      docker|dockerfile)   MATCHES="$MATCHES docker" ;;
      k8s|kubernetes)      MATCHES="$MATCHES kubernetes" ;;
      terraform|tf|hcl)    MATCHES="$MATCHES terraform" ;;
      postgres|postgresql) MATCHES="$MATCHES postgres" ;;
      security|owasp)      MATCHES="$MATCHES security" ;;
      performance|perf)    MATCHES="$MATCHES performance" ;;
      accessibility|a11y)  MATCHES="$MATCHES accessibility" ;;
      electron)            MATCHES="$MATCHES electron" ;;
      websocket|ws)        MATCHES="$MATCHES websocket" ;;
      blockchain|web3)     MATCHES="$MATCHES blockchain" ;;
      gamedev|game)        MATCHES="$MATCHES gamedev" ;;
      iot)                 MATCHES="$MATCHES iot" ;;
      embedded)            MATCHES="$MATCHES embedded" ;;
      fintech)             MATCHES="$MATCHES fintech" ;;
      payment|stripe)      MATCHES="$MATCHES payment" ;;
      seo)                 MATCHES="$MATCHES seo" ;;
      slack)               MATCHES="$MATCHES slack" ;;
      mcp)                 MATCHES="$MATCHES mcp" ;;
      azure)               MATCHES="$MATCHES azure" ;;
      aws|gcp|cloud)       MATCHES="$MATCHES cloud" ;;
      *)
        # Try direct key match in registry
        if awk "/^  ${TOKEN}:/{found=1; exit} END{exit !found}" "$REGISTRY" 2>/dev/null; then
          MATCHES="$MATCHES $TOKEN"
        fi
        ;;
    esac
  done
  # Deduplicate and print (max 2)
  echo "$MATCHES" | tr ' ' '\n' | grep . | sort -u | head -2
  exit $?
fi

# ── --check: verify expert + phase eligibility ──
if [ "${1:-}" = "--check" ]; then
  EXPERT_KEY="${2:-}"
  PHASE="${3:-}"
  if [ -z "$EXPERT_KEY" ] || [ -z "$PHASE" ]; then
    echo "Usage: expert-fetch.sh --check <expert-key> <phase>" >&2
    exit 1
  fi
  USE_IN=$(awk "/^  ${EXPERT_KEY}:/{found=1; next} found && /use_in:/{print; exit}" "$REGISTRY")
  if [ -z "$USE_IN" ]; then
    echo "not-found" && exit 2
  fi
  if echo "$USE_IN" | grep -q "$PHASE"; then
    echo "eligible"
    exit 0
  else
    echo "not-eligible"
    exit 1
  fi
fi

# ── --body: print prompt body without YAML frontmatter ──
if [ "${1:-}" = "--body" ]; then
  EXPERT_KEY="${2:-}"
  CACHE_FILE="$CACHE_DIR/${EXPERT_KEY}.md"
  if [ ! -f "$CACHE_FILE" ]; then
    echo "ERROR: Expert '$EXPERT_KEY' not cached. Run expert-fetch.sh $EXPERT_KEY first." >&2
    exit 1
  fi
  # Strip YAML frontmatter (between --- markers) and print body
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' "$CACHE_FILE"
  exit 0
fi

# ── Standard fetch mode ──
EXPERT_KEY="${1:-}"
FORCE="${2:-}"

if [ -z "$EXPERT_KEY" ]; then
  echo "Usage: expert-fetch.sh <expert-key> [--force]" >&2
  echo "       expert-fetch.sh --detect <ext|tech>..." >&2
  echo "       expert-fetch.sh --body <expert-key>" >&2
  echo "       expert-fetch.sh --list" >&2
  echo "       expert-fetch.sh --check <key> <phase>" >&2
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
