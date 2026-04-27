#!/usr/bin/env bash
set -euo pipefail

REPO="${AAI_REPO:-goodwind-cz/aai}"
REF="${AAI_REF:-main}"
TARGET_ROOT="${AAI_TARGET_ROOT:-$(pwd)}"
SOURCE_ROOT="${AAI_SOURCE_ROOT:-}"
KEEP_TEMP="${AAI_KEEP_TEMP:-0}"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install AAI into the current directory by default.

Options:
  --repo OWNER/REPO       GitHub repository slug (default: goodwind-cz/aai)
  --ref REF              Git ref to download (default: main)
  --target-root PATH     Target project directory (default: current directory)
  --source-root PATH     Local AAI source directory; skips download
  --keep-temp            Keep downloaded temporary files
  -h, --help             Show this help

Environment:
  AAI_REPO, AAI_REF, AAI_TARGET_ROOT, AAI_SOURCE_ROOT, AAI_KEEP_TEMP
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --ref)
      REF="${2:-}"
      shift 2
      ;;
    --target-root)
      TARGET_ROOT="${2:-}"
      shift 2
      ;;
    --source-root)
      SOURCE_ROOT="${2:-}"
      shift 2
      ;;
    --keep-temp)
      KEEP_TEMP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $name" >&2
    exit 1
  fi
}

resolve_existing_directory() {
  local path="$1"
  local label="$2"

  if [[ -z "$path" || ! -d "$path" ]]; then
    echo "ERROR: $label directory does not exist: $path" >&2
    exit 1
  fi

  (cd "$path" && pwd)
}

get_sync_script() {
  local root="$1"
  local sync_script="$root/.aai/scripts/aai-sync.sh"

  if [[ ! -f "$sync_script" ]]; then
    echo "ERROR: AAI sync script not found: $sync_script" >&2
    exit 1
  fi

  printf '%s\n' "$sync_script"
}

download_aai() {
  local repo_slug="$1"
  local git_ref="$2"
  local temp_root="$3"
  local archive_path="$temp_root/aai.tar.gz"
  local url="https://codeload.github.com/$repo_slug/tar.gz/$git_ref"

  if [[ ! "$repo_slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: Repo must be a GitHub owner/repo slug, for example goodwind-cz/aai. Received: $repo_slug" >&2
    exit 1
  fi
  if [[ "$git_ref" == *$'\n'* || "$git_ref" == *$'\r'* ]]; then
    echo "ERROR: Ref must not contain newline characters." >&2
    exit 1
  fi

  require_command curl
  require_command tar

  echo "Downloading AAI from $url" >&2
  curl -fsSL "$url" -o "$archive_path"
  tar -xzf "$archive_path" -C "$temp_root"

  local source
  source="$(
    find "$temp_root" -mindepth 1 -maxdepth 1 -type d \
      -exec test -f '{}/.aai/scripts/aai-sync.sh' ';' -print |
      head -n 1
  )"

  if [[ -z "$source" ]]; then
    echo "ERROR: Downloaded archive does not contain .aai/scripts/aai-sync.sh" >&2
    exit 1
  fi

  printf '%s\n' "$source"
}

TARGET_ROOT="$(resolve_existing_directory "$TARGET_ROOT" "Target")"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-install-XXXXXXXXXX")"
TEMP_CREATED=0

cleanup() {
  if [[ "$TEMP_CREATED" == "1" && "$KEEP_TEMP" != "1" && -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  elif [[ "$TEMP_CREATED" == "1" && "$KEEP_TEMP" == "1" ]]; then
    echo "Kept temporary installer files at: $TEMP_ROOT"
  fi
}
trap cleanup EXIT

if [[ -z "$SOURCE_ROOT" ]]; then
  TEMP_CREATED=1
  SOURCE_ROOT="$(download_aai "$REPO" "$REF" "$TEMP_ROOT")"
else
  SOURCE_ROOT="$(resolve_existing_directory "$SOURCE_ROOT" "Source")"
fi

SYNC_SCRIPT="$(get_sync_script "$SOURCE_ROOT")"

echo "Installing AAI into: $TARGET_ROOT"
bash "$SYNC_SCRIPT" "$TARGET_ROOT"

for path in \
  ".aai/AGENTS.md" \
  ".aai/workflow/WORKFLOW.md" \
  ".aai/scripts/aai-sync.sh" \
  "CODEX.md" \
  "SKILLS.md"
do
  if [[ ! -e "$TARGET_ROOT/$path" ]]; then
    echo "ERROR: Install verification failed. Missing expected path: $path" >&2
    exit 1
  fi
done

cat <<'EOF'

AAI installed.
Next:
  git status
  git diff
  /aai-bootstrap
  /aai-doctor
EOF
