#!/usr/bin/env bash
# Pre-commit quality gate checks for AAI projects
# Source: Inspired by pro-workflow quality gates (https://github.com/rohitg00/pro-workflow)
#
# Usage: Called from AAI skills before git commit, or as a standalone check.
#   bash .aai/scripts/pre-commit-checks.sh [--strict]
#
# Exit codes:
#   0 = all checks pass (warnings may exist)
#   1 = blocking errors found (commit should be prevented)
#
# --strict: treat warnings as errors

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STRICT="${1:-}"
ERRORS=0
WARNINGS=0

# Colors (if terminal supports them)
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

error() { echo -e "${RED}✗ $1${NC}"; ERRORS=$((ERRORS+1)); }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; WARNINGS=$((WARNINGS+1)); }
pass()  { echo -e "${GREEN}✓ $1${NC}"; }

echo "─────────────────────────────────────"
echo "PRE-COMMIT QUALITY GATES"
echo "─────────────────────────────────────"
echo ""

# --- CHECK 1: TDD Evidence Complete ---
STATE_FILE="$PROJECT_ROOT/docs/ai/STATE.yaml"
if [ -f "$STATE_FILE" ]; then
  STATE_DATA=$(grep -v '^[[:space:]]*#' "$STATE_FILE" 2>/dev/null || true)
  # Check if there's an active work item in implementation phase
  # Simple heuristic: look for phase: implementation without corresponding validation pass
  if echo "$STATE_DATA" | grep -q "phase:.*implementation"; then
    LAST_VALIDATION_BLOCK=$(echo "$STATE_DATA" | awk '
      /^last_validation:/ { flag=1; next }
      /^[^[:space:]]/ { flag=0 }
      flag { print }
    ')
    if ! echo "$LAST_VALIDATION_BLOCK" | grep -q "status: *pass"; then
      warn "TDD cycle may be incomplete — active implementation without validation pass"
    else
      pass "TDD evidence appears complete"
    fi
  else
    pass "No active implementation phase"
  fi
else
  warn "STATE.yaml not found — skipping TDD check"
fi

# --- CHECK 2: Secrets Detection ---
STAGED_FILES=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null || true)
SECRETS_FOUND=0

if [ -n "$STAGED_FILES" ]; then
  while IFS= read -r file; do
    filepath="$PROJECT_ROOT/$file"
    [ -f "$filepath" ] || continue

    # Check for common secret patterns
    if grep -qEi "(api[_-]?key|api[_-]?secret|password|passwd|secret[_-]?key|access[_-]?token|private[_-]?key)\s*[:=]\s*[\"'][^\"']{8,}" "$filepath" 2>/dev/null; then
      error "Potential secret detected in $file"
      SECRETS_FOUND=1
    fi

    # Check for .env files
    if [[ "$file" == *.env* ]] || [[ "$file" == *credentials* ]] || [[ "$file" == *secret* ]]; then
      error "Sensitive file staged: $file"
      SECRETS_FOUND=1
    fi
  done <<< "$STAGED_FILES"

  if [ "$SECRETS_FOUND" -eq 0 ]; then
    pass "No secrets detected in staged files"
  fi
else
  pass "No staged files to check"
fi

# --- CHECK 3: Debug Statements ---
DEBUG_FOUND=0
if [ -n "$STAGED_FILES" ]; then
  while IFS= read -r file; do
    filepath="$PROJECT_ROOT/$file"
    [ -f "$filepath" ] || continue

    # Skip non-source files
    case "$file" in
      *.md|*.yaml|*.yml|*.json|*.jsonl|*.txt|*.sh|*.ps1|*.gitignore) continue ;;
    esac

    # Check for debug statements
    matches=$(grep -n 'console\.log\|debugger\|pdb\.set_trace\|binding\.pry\|var_dump' "$filepath" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      warn "Debug statements in $file:"
      echo "$matches" | head -3 | sed 's/^/    /'
      DEBUG_FOUND=1
    fi
  done <<< "$STAGED_FILES"

  if [ "$DEBUG_FOUND" -eq 0 ]; then
    pass "No debug statements found"
  fi
fi

# --- CHECK 4: TODO/FIXME markers ---
TODO_COUNT=0
if [ -n "$STAGED_FILES" ]; then
  while IFS= read -r file; do
    filepath="$PROJECT_ROOT/$file"
    [ -f "$filepath" ] || continue
    case "$file" in
      *.md|*.yaml|*.yml|*.txt|*.sh|*.ps1) continue ;;
    esac

    count=$(grep -c 'TODO\|FIXME\|HACK\|XXX' "$filepath" 2>/dev/null || true)
    if [ "$count" -gt 0 ]; then
      TODO_COUNT=$((TODO_COUNT + count))
    fi
  done <<< "$STAGED_FILES"

  if [ "$TODO_COUNT" -gt 0 ]; then
    warn "$TODO_COUNT TODO/FIXME markers in staged files"
  else
    pass "No TODO/FIXME markers"
  fi
fi

# --- CHECK 5: Validation Report ---
if [ -f "$STATE_FILE" ]; then
  STATE_DATA=$(grep -v '^[[:space:]]*#' "$STATE_FILE" 2>/dev/null || true)
  LAST_VALIDATION_BLOCK=$(echo "$STATE_DATA" | awk '
    /^last_validation:/ { flag=1; next }
    /^[^[:space:]]/ { flag=0 }
    flag { print }
  ')
  if echo "$STATE_DATA" | grep -q "phase:.*validation" ||
     echo "$LAST_VALIDATION_BLOCK" | grep -q "status: *pass"; then
    REPORTS_DIR="$PROJECT_ROOT/docs/ai/reports"
    if [ -d "$REPORTS_DIR" ] && {
      ls "$REPORTS_DIR"/validation-*.md 1>/dev/null 2>&1 ||
      ls "$REPORTS_DIR"/VALIDATION_REPORT_*.md 1>/dev/null 2>&1 ||
      [ -f "$REPORTS_DIR/LATEST.md" ]
    }; then
      pass "Validation report exists"
    else
      warn "No validation report found — consider running /aai-validate-report"
    fi
  fi
fi

# --- CHECK 6: Code Review Gate ---
if [ -f "$STATE_FILE" ]; then
  CODE_REVIEW_BLOCK=$(awk '
    /^code_review:/ { flag=1; next }
    /^[^[:space:]]/ { flag=0 }
    flag { print }
  ' "$STATE_FILE")
  if echo "$CODE_REVIEW_BLOCK" | grep -q "required: *true"; then
    if echo "$CODE_REVIEW_BLOCK" | grep -qE "status: *(pass|waived)"; then
      pass "Code review gate satisfied"
    else
      warn "Code review required but not pass/waived"
    fi
  fi
fi

# --- CHECK 7: PowerShell parse gate ---
# A staged .ps1 with a parse error breaks /aai-update et al. for Windows users
# silently (the failure only surfaces when they run it). If pwsh is available,
# parse-check every staged .ps1 so a broken script can't land. No-op when pwsh is
# absent (most macOS/Linux dev boxes) — the full gate runs in tests/skills/.
STAGED_PS1=$(git -C "$PROJECT_ROOT" diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.ps1$' || true)
if [ -n "$STAGED_PS1" ]; then
  if command -v pwsh >/dev/null 2>&1; then
    PS1_BAD=0
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      [ -f "$PROJECT_ROOT/$f" ] || continue
      if ! pwsh -NoProfile -Command "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('$PROJECT_ROOT/$f', [ref]\$null, [ref]\$e) | Out-Null; if (\$e -and \$e.Count) { exit 1 } else { exit 0 }" >/dev/null 2>&1; then
        error "PowerShell parse error in staged $f"
        PS1_BAD=$((PS1_BAD+1))
      fi
    done <<< "$STAGED_PS1"
    [ "$PS1_BAD" -eq 0 ] && pass "Staged .ps1 scripts parse cleanly"
  else
    warn "Staged .ps1 changes not parse-checked (pwsh not installed)"
  fi
fi

# --- CHECK 8: Doc-numbering guards (SPEC-0015 / RFC-0007) ---
# Two predicates, report-only by DEFAULT (mirroring close_gate / body_lint),
# flippable to enforce via docs/ai/docs-audit.yaml `doc_number_guard: enforce`:
#   - no-DRAFT-at-merge: any docs/*/*-DRAFT-*.md, or a governed doc still carrying
#     `number: null`, present at the merge/commit point.
#   - duplicate-number: two governed docs of the same type resolving to the same
#     TYPE-000N (same type + number, or identical numeric filename prefixes).
# A clean, fully-numbered tree passes both with exit 0. The allocator engine
# (`--guard`) is the single source of truth for both predicates.
# NOTE (CHANGE-0009 D8): this grep is a deliberate THIN mirror of the guard
# dial; the CANONICAL reader of docs-audit.yaml is .aai/scripts/lib/guard-config.mjs
# (a conformance test asserts this pattern and the reader agree on fixtures).
DOC_NUMBER_GUARD="$PROJECT_ROOT/.aai/scripts/allocate-doc-number.mjs"
if [ -f "$DOC_NUMBER_GUARD" ] && command -v node >/dev/null 2>&1; then
  DN_MODE="report-only"
  if grep -Eq '^doc_number_guard:[[:space:]]*enforce([[:space:]]|$)' \
       "$PROJECT_ROOT/docs/ai/docs-audit.yaml" 2>/dev/null; then
    DN_MODE="enforce"
  fi
  # Merge-point-aware enforce (shipped-guards-have-no-downstream-trigger D2):
  # the AAI flow COMMITS drafts on branches by design (numbering is assigned
  # at merge by the allocator), so `no-DRAFT-at-merge` has a legitimate
  # false positive at commit time on any non-default branch — measured, an
  # enforce dial refused this repository's own intake commits once the
  # pre-commit hook started reaching this script. `enforce` therefore bites
  # on the DEFAULT branch only (R1: refs/remotes/origin/HEAD, else main) and
  # downgrades to report-only elsewhere with ONE line saying so.
  DN_DEFAULT="$(git -C "$PROJECT_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  DN_DEFAULT="${DN_DEFAULT#origin/}"
  if [ -z "$DN_DEFAULT" ]; then
    DN_DEFAULT="main"
    echo "    NOTE: default branch assumed main (refs/remotes/origin/HEAD unset)"
  fi
  DN_BRANCH="$(git -C "$PROJECT_ROOT" symbolic-ref -q --short HEAD 2>/dev/null || true)"
  [ -n "$DN_BRANCH" ] || DN_BRANCH="(detached HEAD)"
  DN_DOWNGRADE=""
  if [ "$DN_MODE" = "enforce" ] && ! [ "$DN_BRANCH" = "$DN_DEFAULT" ]; then
    DN_MODE="report-only"
    DN_DOWNGRADE="Doc-numbering guard: enforce applies on $DN_DEFAULT only; on $DN_BRANCH this is report-only"
  fi
  if DN_OUT="$(cd "$PROJECT_ROOT" && node "$DOC_NUMBER_GUARD" --guard 2>&1)"; then
    pass "Doc-numbering guards clean (no-DRAFT-at-merge + duplicate-number)"
  elif [ "$DN_MODE" = "enforce" ]; then
    error "Doc-numbering guard failed (doc_number_guard: enforce) — commit blocked:"
    echo "$DN_OUT" | sed 's/^/    /'
  else
    warn "Doc-numbering guard found violations (report-only; commit allowed):"
    echo "$DN_OUT" | sed 's/^/    /'
    [ -z "$DN_DOWNGRADE" ] || echo "    $DN_DOWNGRADE"
  fi
else
  pass "Doc-numbering guard skipped (allocator absent or node unavailable)"
fi

# --- CHECK 9: Gitignored paths staged (post-validation-pushes-reuse-test-results D3) ---
# tracked-ignored.mjs --staged is the one predicate (repository .gitignore
# rules only; core.excludesFile and .git/info/exclude are not counted). An
# ADDED ignored path (git add -f, copy or rename destination) blocks; a
# MODIFIED already-tracked one warns (blocking only under --strict); a
# deletion passes. The remedy for deliberate tracking is a `!<path>`
# re-include in .gitignore, which is reviewable; there is no env bypass.
TRACKED_IGNORED_SCRIPT="$PROJECT_ROOT/.aai/scripts/tracked-ignored.mjs"
if [ -f "$TRACKED_IGNORED_SCRIPT" ] && command -v node >/dev/null 2>&1; then
  TI_RC=0
  TI_OUT="$(node "$TRACKED_IGNORED_SCRIPT" --staged 2>&1)" || TI_RC=$?
  if [ "$TI_RC" -gt 1 ]; then
    warn "Gitignored-path check could not run (tracked-ignored.mjs exit $TI_RC) — skipped"
    echo "$TI_OUT" | sed 's/^/    /'
  else
    TI_SEEN=0
    while IFS= read -r TI_LINE; do
      case "$TI_LINE" in
        "IGNORED_ADDED "*)
          TI_REST="${TI_LINE#IGNORED_ADDED }"
          TI_PATH="${TI_REST% rule=*}"; TI_RULE="${TI_REST##* rule=}"
          TI_SEEN=1
          error "Gitignored path staged for ADD: $TI_PATH (rule $TI_RULE) — to track it deliberately add \"!$TI_PATH\" to .gitignore; otherwise unstage it: git rm --cached -- \"$TI_PATH\""
          ;;
        "IGNORED_MODIFIED "*)
          TI_REST="${TI_LINE#IGNORED_MODIFIED }"
          TI_PATH="${TI_REST% rule=*}"; TI_RULE="${TI_REST##* rule=}"
          TI_SEEN=1
          warn "Tracked path matched by .gitignore is modified: $TI_PATH (rule $TI_RULE) — untrack it (git rm --cached) or re-include it with \"!$TI_PATH\""
          ;;
        "IGNORED_PREEXISTING count="*)
          TI_SEEN=1
          warn "${TI_LINE#IGNORED_PREEXISTING count=} tracked path(s) already match .gitignore (not touched by this commit) — run: node .aai/scripts/tracked-ignored.mjs --all"
          ;;
      esac
    done <<TIEOF
$TI_OUT
TIEOF
    [ "$TI_SEEN" -eq 1 ] || pass "No gitignored path staged"
  fi
else
  warn "Gitignored-path check skipped (tracked-ignored.mjs absent or node unavailable)"
fi

# --- SUMMARY ---
echo ""
echo "─────────────────────────────────────"
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}BLOCKED: $ERRORS error(s), $WARNINGS warning(s)${NC}"
  echo "Fix errors before committing."
  exit 1
elif [ "$WARNINGS" -gt 0 ] && [ "$STRICT" = "--strict" ]; then
  echo -e "${YELLOW}BLOCKED (strict mode): $WARNINGS warning(s)${NC}"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}PASS WITH WARNINGS: $WARNINGS warning(s)${NC}"
  exit 0
else
  echo -e "${GREEN}ALL CHECKS PASS${NC}"
  exit 0
fi
