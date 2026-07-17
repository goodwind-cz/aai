#!/usr/bin/env bash
# AAI layer updater — one deterministic command for /aai-update.
#
# Materializes the canonical AAI repo's `main`, runs aai-sync into THIS project,
# and prints concise post-sync evidence. Replaces the old 7-step agent-narrated
# procedure: the agent now runs this once and relays the final report.
#
# Usage (run from the TARGET project root):
#   ./.aai/scripts/aai-update.sh                       # sync from goodwind-cz/aai@main
#   ./.aai/scripts/aai-update.sh --dry-run             # print the plan, change nothing
#   ./.aai/scripts/aai-update.sh --repo OWNER/NAME     # alternate upstream slug
#   ./.aai/scripts/aai-update.sh --repo ../aai         # alternate upstream: local checkout
#   ./.aai/scripts/aai-update.sh --repo git@github.com:OWNER/NAME.git
#   ./.aai/scripts/aai-update.sh --ref some-branch     # non-default ref
#   ./.aai/scripts/aai-update.sh --keep-temp           # keep the temp clone for inspection
#   ./.aai/scripts/aai-update.sh --force               # allow running inside the canonical repo
set -euo pipefail

# Self-relocate to a temp copy so the sync (which overwrites .aai/scripts/) can
# never pull this script out from under a running bash. cwd is preserved by exec.
if [[ "${AAI_UPDATE_RELOCATED:-0}" != "1" ]]; then
  _self_copy="$(mktemp "${TMPDIR:-/tmp}/aai-update.XXXXXX")"
  cat "$0" > "$_self_copy"
  AAI_UPDATE_RELOCATED=1 exec bash "$_self_copy" "$@"
fi

REPO="goodwind-cz/aai"
REF="main"
DRY_RUN=0
KEEP_TEMP=0
FORCE=0
TARGET="$(pwd)"
TMP=""
SRCDIR=""

# Set the cleanup trap immediately so even early exits (--help, guard refusal)
# remove this relocated self-copy. TMP is filled in later; cleanup tolerates empty.
cleanup() {
  [[ "${KEEP_TEMP:-0}" != "1" && -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"
  rm -f "$0" 2>/dev/null || true
}
trap cleanup EXIT

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO="${2:?--repo needs a value}"; shift 2 ;;
    --ref)       REF="${2:?--ref needs a value}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    --force)     FORCE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Normalize a slug / https / ssh remote to lowercase "owner/repo"; empty for paths.
norm_slug() {
  local s="${1:-}"
  s="${s%.git}"
  s="${s##*github.com[:/]}"
  if [[ "$s" =~ ^[^/]+/[^/]+$ ]]; then printf '%s' "$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"; fi
}

# Canonical-repo guard: refuse to sync the AAI repo into itself.
target_origin="$(git -C "$TARGET" config --get remote.origin.url 2>/dev/null || true)"
if [[ -n "$(norm_slug "$REPO")" && "$(norm_slug "$target_origin")" == "$(norm_slug "$REPO")" && "$FORCE" != "1" ]]; then
  echo "REFUSED: this project ($target_origin) looks like the canonical AAI repo." >&2
  echo "  /aai-update syncs AAI INTO a target project; update the canonical repo with normal git." >&2
  echo "  Pass --force to override." >&2
  exit 2
fi

# Resolve <SOURCE>: an existing local checkout, or a fresh shallow clone.
if [[ -d "$REPO" ]]; then
  SRC="$(cd "$REPO" && pwd)"
  git -C "$SRC" fetch --depth 1 origin "$REF" >/dev/null 2>&1 || true
  git -C "$SRC" checkout "$REF" >/dev/null 2>&1 || true
  git -C "$SRC" pull --ff-only origin "$REF" >/dev/null 2>&1 || true
  SRC_DESC="local checkout $SRC"
else
  if [[ "$REPO" == *://* || "$REPO" == *@*:* ]]; then CLONE_URL="$REPO"; else CLONE_URL="https://github.com/$REPO.git"; fi
  if [[ "$DRY_RUN" != "1" ]]; then
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/aai-src.XXXXXX")"
    SRCDIR="$TMP/src"
    cloned=0
    # git refuses to clone into a non-empty dir, and a failed attempt leaves a
    # partial one behind — so wipe SRCDIR before every attempt. TMP itself is the
    # securely-owned mktemp parent and is NEVER rm-rf'd-and-recreated mid-run
    # (ISSUE-0012 TOCTOU fix): only the SRCDIR subdirectory is wiped between
    # attempts, so the ownership guarantee on the parent is never up for grabs.
    if command -v gh >/dev/null 2>&1; then
      rm -rf "$SRCDIR"
      gh repo clone "$REPO" "$SRCDIR" -- --branch "$REF" --depth 1 >/dev/null 2>&1 && cloned=1
    fi
    if [[ "$cloned" != "1" ]]; then
      rm -rf "$SRCDIR"
      git clone --branch "$REF" --depth 1 "$CLONE_URL" "$SRCDIR" >/dev/null 2>&1 && cloned=1
    fi
    if [[ "$cloned" != "1" ]]; then
      # Last resort: a truly anonymous clone. On a machine where `gh auth setup-git`
      # wired gh in as git's credential helper, a broken/expired token gets injected
      # even into the plain `git clone` above — 401-ing a PUBLIC repo that needs no
      # auth at all. Emptying the credential helper + any injected auth header forces
      # git to fetch anonymously, so the public canonical repo clones with no creds.
      rm -rf "$SRCDIR"
      GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c http.https://github.com/.extraheader= \
          clone --branch "$REF" --depth 1 "$CLONE_URL" "$SRCDIR" >/dev/null 2>&1 && cloned=1  # PR#67 review NB-1: never prompt (agent sessions would hang)
    fi
    if [[ "$cloned" != "1" ]]; then
      echo "ERROR: could not fetch $REPO@$REF (auth or network?). Treat as an access issue, not a missing repo." >&2
      exit 3
    fi
  fi
  SRC="$SRCDIR"
  SRC_DESC="$CLONE_URL@$REF"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "## aai-update (dry-run) — no files changed"
  echo "- Target:   $TARGET"
  echo "- Upstream: ${SRC_DESC:-$REPO@$REF}"
  echo "- Would run: <source>/.aai/scripts/aai-sync.sh \"$TARGET\""
  echo "- Then check: git status --short, .aai/system/AAI_PIN.md, docs/ai/reports/sync-conflicts-*.md"
  echo "- Next: /aai-doctor (and /aai-bootstrap if skills changed)"
  exit 0
fi

SYNC="$SRC/.aai/scripts/aai-sync.sh"
[[ -f "$SYNC" ]] || { echo "ERROR: sync script missing in source: $SYNC" >&2; exit 4; }

echo "## aai-update — syncing $SRC_DESC into $TARGET"
bash "$SYNC" "$TARGET"

echo
echo "## Post-sync evidence"
changed="$(git -C "$TARGET" status --short 2>/dev/null || true)"
if [[ -n "$changed" ]]; then
  n="$(printf '%s\n' "$changed" | wc -l | tr -d ' ')"
  echo "- Changed files ($n):"
  printf '%s\n' "$changed" | sed 's/^/  /'
else
  echo "- Changed files: none (already up to date)"
fi

if [[ -f "$TARGET/.aai/system/AAI_PIN.md" ]]; then
  echo "- AAI_PIN:"
  grep -iE 'source|version|commit|canonical|ref' "$TARGET/.aai/system/AAI_PIN.md" | sed 's/^/  /' || true
fi

latest_conflict="$(ls -t "$TARGET"/docs/ai/reports/sync-conflicts-*.md 2>/dev/null | head -1 || true)"
if [[ -n "$latest_conflict" ]]; then
  echo "- ⚠ Conflict advisory: ${latest_conflict#$TARGET/} — review before committing."
fi

echo
echo "## Next"
echo "- Review the diff (git diff), then commit manually (this tool never auto-commits)."
echo "- Recommended: /aai-doctor${changed:+ ; /aai-bootstrap if skills/indexes changed}"
