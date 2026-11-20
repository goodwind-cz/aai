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

# IN_REPO: is there a git directory (so an index) to judge? `--git-dir` succeeds in a work tree, inside
# `.git` and with GIT_DIR set, and fails only where there is no repository at all.
IN_REPO=0
git rev-parse --git-dir >/dev/null 2>&1 && IN_REPO=1
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || PROJECT_ROOT="$(pwd)"
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

# No check below uses a here-string, a here-document or a redirection on a builtin: when the descriptor table is
# nearly full, bash 3.2 cannot save a descriptor for such a redirection, applies it anyway and never restores it, so
# the rest of the report went to /dev/null. STATE is matched in the shell (`[[ =~ ]]`, per line as grep did), a line
# list is walked by parameter expansion, and a tool is looked up in a forked subshell, ( command -v node ).
PCC_RE_IMPL=$'phase:[^\n]*implementation'
PCC_RE_VALID=$'phase:[^\n]*validation'
PCC_RE_PASS='status: *pass'
PCC_RE_REQUIRED='required: *true'
PCC_RE_REVIEW_OK='status: *(pass|waived)'
# pcc_next_line: moves the first line of PCC_REST into PCC_LINE and drops it from PCC_REST.
pcc_next_line() {
  PCC_LINE="${PCC_REST%%$'\n'*}"
  case "$PCC_REST" in
    *$'\n'*) PCC_REST="${PCC_REST#*$'\n'}" ;;
    *) PCC_REST="" ;;
  esac
}

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
  if [[ "$STATE_DATA" =~ $PCC_RE_IMPL ]]; then
    LAST_VALIDATION_BLOCK=$(echo "$STATE_DATA" | awk '
      /^last_validation:/ { flag=1; next }
      /^[^[:space:]]/ { flag=0 }
      flag { print }
    ')
    if ! [[ "$LAST_VALIDATION_BLOCK" =~ $PCC_RE_PASS ]]; then
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

# --- Staged content: one batched index read ---
# CHECKs 2-4 judge what the commit records, not the working tree. The staged
# list comes from ONE `git diff --cached --raw -z` (NUL-separated, so a name git
# would quote is checked under its real path), and the blobs of every record
# that has a stage-0 object come from ONE `git cat-file --batch`, asked by
# object id. Each response is parsed by its declared size and copied to a
# scratch file; any shortfall (truncated, dropped, extra or misaligned output,
# a missing object, a failed write) blocks the commit instead of letting the
# checks scan less than was staged. A deletion, an unmerged path and a gitlink
# have no stage-0 blob and are skipped. Where no git directory exists at all
# (IN_REPO=0, a plain directory) there is nothing to judge: no scratch directory
# is made and the checks report no staged files, as before. Wherever one exists
# (a work tree, a cwd inside `.git`, GIT_DIR set) every failure blocks.
# Descriptor safety: when the descriptor table is nearly full, bash 3.2 cannot
# save a descriptor for a builtin's redirection (a here-string read, `read <&3`,
# `: >`), prints "cannot duplicate fd", applies the redirection anyway and
# never restores stdin, which ended a read loop after its first record. So the
# parse uses no builtin redirection: the list and the batch file are opened
# once with `exec` on descriptors 4 and 3 and read with `read -u`, the record
# is split by parameter expansion, and a copy is created by `dd` (an external
# command redirects in its own process). As defence in depth the counts are
# checked by tools that are not this loop: the NUL terminators of the list file
# (`tr`, `wc -c`) must be twice the parsed records, one more
# `git diff --cached --name-only -z` must name as many paths as were parsed,
# and the number of copies must equal the number of requests. The two
# descriptors stay open until the process ends; the EXIT trap runs `rm -rf` with 3 and 4 closed in the
# child (an external command's redirection is made there, so it needs no save), which leaves it the free
# descriptor it needs to walk the scratch directory when the table is nearly full.
# A size is a decimal without a leading zero (bash reads `028` as a bad octal) and at most 15 digits;
# a `PCC_PARSED` sentinel, set to 0 here and checked by a separate command wherever a git directory exists,
# blocks any abort of either block below.
staged_read_fail() {
  error "Staged content could not be read completely: $1 — commit blocked"
  exit 1
}
STAGED=()
STAGED_SHA=()
STAGED_BLOB=()
STAGED_REQ=()
PCC_TMP=""
PCC_LIST=0
PCC_PARSED=0
if [ "$IN_REPO" -eq 1 ]; then
  PCC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/aai-pre-commit.XXXXXX" 2>/dev/null)" || staged_read_fail "cannot create a scratch directory"
  trap 'rm -rf "$PCC_TMP" 3<&- 4<&-' EXIT
  # The NUL terminators of both lists are counted (by tr and wc, not the parse) before the parse. Another process
  # can change the index between the two reads: when the list's count is even and is not twice the names' count,
  # both are read once more. The loop stops after the second read whatever it finds, and at once on an odd list
  # count (malformed, not a race); the post-parse checks below judge the last pair and still block a mismatch.
  pcc_try=1
  while :; do
    git -C "$PROJECT_ROOT" diff --cached --raw -z --no-renames --no-abbrev --no-color > "$PCC_TMP/list" 2>/dev/null || staged_read_fail "git diff --cached failed"
    git -C "$PROJECT_ROOT" diff --cached --name-only -z --no-renames --no-color > "$PCC_TMP/names" 2>/dev/null || staged_read_fail "git diff --cached failed"
    tr -cd '\000' < "$PCC_TMP/list" > "$PCC_TMP/list.nul" || staged_read_fail "malformed staged list"
    nul="$(wc -c < "$PCC_TMP/list.nul")" || staged_read_fail "malformed staged list"
    tr -cd '\000' < "$PCC_TMP/names" > "$PCC_TMP/names.nul" || staged_read_fail "staged list count mismatch"
    nnames="$(wc -c < "$PCC_TMP/names.nul")" || staged_read_fail "staged list count mismatch"
    if [ "$pcc_try" -ge 2 ] || [ $((nul % 2)) -eq 1 ] || [ "$nul" -eq $((nnames * 2)) ]; then break; fi
    pcc_try=$((pcc_try + 1))
  done
  PCC_LIST=1
fi
if [ "$PCC_LIST" -eq 1 ]; then
  meta=""
  nrec=0
  exec 4< "$PCC_TMP/list" || staged_read_fail "git diff --cached failed"
  while IFS= read -r -d '' -u 4 meta; do
    IFS= read -r -d '' -u 4 f || staged_read_fail "malformed staged list"
    case "$meta" in :*) ;; *) staged_read_fail "malformed staged list" ;; esac
    rest="${meta#:}"
    spaces="${rest//[!\ ]/}"
    [ "${#spaces}" -eq 4 ] || staged_read_fail "malformed staged list"
    rest="${rest#* }"
    mode="${rest%% *}"
    rest="${rest#* }"
    rest="${rest#* }"
    sha="${rest%% *}"
    st="${rest#* }"
    nrec=$((nrec + 1))
    STAGED+=("$f")
    case "$st" in
      D|U) STAGED_SHA+=("") ;;
      *)
        if [ "$mode" = 160000 ]; then
          STAGED_SHA+=("")
        else
          case "$sha" in ''|*[!0-9a-f]*) staged_read_fail "malformed staged list" ;; esac
          case "$sha" in *[!0]*) ;; *) staged_read_fail "malformed staged list" ;; esac
          [ "${#sha}" -eq 40 ] || [ "${#sha}" -eq 64 ] || staged_read_fail "malformed staged list"
          STAGED_SHA+=("$sha")
          STAGED_REQ+=("$sha")
        fi
        ;;
    esac
    meta=""
  done
  [ -z "$meta" ] || staged_read_fail "malformed staged list"
  [ "$nul" -eq $((nrec * 2)) ] || staged_read_fail "malformed staged list"
  [ "$nnames" -eq "$nrec" ] || staged_read_fail "staged list count mismatch"
  if [ "${#STAGED_REQ[@]}" -gt 0 ]; then
    # A pipeline whose pipe cannot be made ends bash itself (exit 129, no report), while a command substitution
    # that cannot make one comes back empty: one is tried first, so a table too full for the pipe blocks here.
    pcc_probe="$(echo ok)"
    [ "$pcc_probe" = ok ] || staged_read_fail "git cat-file --batch failed"
    printf '%s\n' "${STAGED_REQ[@]}" | git -C "$PROJECT_ROOT" cat-file --batch > "$PCC_TMP/batch" 2>/dev/null || staged_read_fail "git cat-file --batch failed"
    exec 3< "$PCC_TMP/batch" || staged_read_fail "git cat-file --batch failed"
    for idx in "${!STAGED_SHA[@]}"; do
      sha="${STAGED_SHA[$idx]}"
      STAGED_BLOB[$idx]=""
      [ -n "$sha" ] || continue
      file="${STAGED[$idx]}"
      IFS= read -r -u 3 hdr || staged_read_fail "response missing for $file"
      size=""
      case "$hdr" in "$sha blob "*) size="${hdr#"$sha blob "}" ;; esac
      case "$size" in ''|*[!0-9]*|0?*) staged_read_fail "unexpected response for $file" ;; esac
      [ "${#size}" -le 15 ] || staged_read_fail "unexpected response for $file"
      obj="$PCC_TMP/$idx"
      big=$((size / 1048576))
      rem=$((size % 1048576))
      if [ "$size" -eq 0 ]; then
        dd if=/dev/null of="$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
      elif [ "$big" -gt 0 ]; then
        dd bs=1048576 count="$big" <&3 > "$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
        if [ "$rem" -gt 0 ]; then
          dd bs="$rem" count=1 <&3 >> "$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
        fi
      else
        dd bs="$rem" count=1 <&3 > "$obj" 2>/dev/null || staged_read_fail "copy failed for $file"
      fi
      got="$(wc -c < "$obj")" || staged_read_fail "size mismatch for $file"
      [ "$got" -eq "$size" ] || staged_read_fail "size mismatch for $file"
      sep="x"
      IFS= read -r -u 3 sep || staged_read_fail "separator missing after $file"
      [ -z "$sep" ] || staged_read_fail "separator missing after $file"
      STAGED_BLOB[$idx]="$obj"
    done
    extra=""
    if IFS= read -r -u 3 extra || [ -n "$extra" ]; then staged_read_fail "unrequested trailing output"; fi
  fi
  ncopy=0
  if [ "${#STAGED_BLOB[@]}" -gt 0 ]; then
    for obj in "${STAGED_BLOB[@]}"; do
      [ -z "$obj" ] || ncopy=$((ncopy + 1))
    done
  fi
  [ "$ncopy" -eq "${#STAGED_REQ[@]}" ] || staged_read_fail "copy count mismatch"
  PCC_PARSED=1
fi
# A shell that aborts an arithmetic or expansion error drops the whole `if` block it is in and goes on with rc 0, count
# cross-checks included; this separate command makes any such abort block the commit. It is keyed on IN_REPO, not
# PCC_LIST, so an abort before the list flag is set blocks too, and PCC_PARSED is set above, never inherited.
[ "$IN_REPO" -eq 0 ] || [ "$PCC_PARSED" -eq 1 ] || staged_read_fail "parse did not complete"

# --- CHECK 2: Secrets Detection ---
SECRETS_FOUND=0

if [ "${#STAGED[@]}" -gt 0 ]; then
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    blob="${STAGED_BLOB[$idx]:-}"
    [ -n "$blob" ] || continue

    # Check for common secret patterns in the staged blob (what the commit records). A copy that cannot be
    # opened must not read as zero hits: grep -c always prints a number, so anything else is a failed scan.
    [ -f "$blob" ] && [ -r "$blob" ] || staged_read_fail "copy failed for $file"
    hits=$(grep -cEi "(api[_-]?key|api[_-]?secret|password|passwd|secret[_-]?key|access[_-]?token|private[_-]?key)\s*[:=]\s*[\"'][^\"']{8,}" < "$blob" || true)
    case "$hits" in ''|*[!0-9]*) staged_read_fail "copy failed for $file" ;; esac
    if [ "$hits" -gt 0 ]; then
      error "Potential secret detected in $file"
      SECRETS_FOUND=1
    fi

    # Name check. AAI evidence folders are judged by content alone, except a dotenv file.
    name_check=1
    case "$file" in
      docs/ai/reports/*|docs/ai/tdd/*|docs/ai/validation/*|docs/ai/reviews/*) name_check=0 ;;
    esac
    case "${file##*/}" in
      .env|.env.*|*.env) name_check=1 ;;
    esac
    if [ "$name_check" -eq 1 ] && { [[ "$file" == *.env* ]] || [[ "$file" == *credentials* ]] || [[ "$file" == *secret* ]]; }; then
      error "Sensitive file staged: $file"
      SECRETS_FOUND=1
    fi
  done

  if [ "$SECRETS_FOUND" -eq 0 ]; then
    pass "No secrets detected in staged files"
  fi
else
  pass "No staged files to check"
fi

# --- CHECK 3: Debug Statements ---
DEBUG_FOUND=0
if [ "${#STAGED[@]}" -gt 0 ]; then
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    blob="${STAGED_BLOB[$idx]:-}"
    [ -n "$blob" ] || continue

    # Skip non-source files
    case "$file" in
      *.md|*.yaml|*.yml|*.json|*.jsonl|*.txt|*.sh|*.ps1|*.gitignore) continue ;;
    esac

    # Check for debug statements
    [ -f "$blob" ] && [ -r "$blob" ] || staged_read_fail "copy failed for $file"
    matches=$(grep -n 'console\.log\|debugger\|pdb\.set_trace\|binding\.pry\|var_dump' < "$blob" || true)
    if [ -n "$matches" ]; then
      warn "Debug statements in $file:"
      PCC_REST="$matches"
      PCC_SHOWN=0
      while [ -n "$PCC_REST" ] && [ "$PCC_SHOWN" -lt 3 ]; do
        pcc_next_line
        echo "    $PCC_LINE"
        PCC_SHOWN=$((PCC_SHOWN + 1))
      done
      DEBUG_FOUND=1
    fi
  done

  if [ "$DEBUG_FOUND" -eq 0 ]; then
    pass "No debug statements found"
  fi
fi

# --- CHECK 4: TODO/FIXME markers ---
TODO_COUNT=0
if [ "${#STAGED[@]}" -gt 0 ]; then
  for idx in "${!STAGED[@]}"; do
    file="${STAGED[$idx]}"
    blob="${STAGED_BLOB[$idx]:-}"
    [ -n "$blob" ] || continue
    # Keep this skip list a subset of CHECK 3's: CHECK 4 re-tests every copy CHECK 3 reads, so a copy that vanishes
    # while CHECK 3 reads it (and reads as no matches there) blocks here.
    case "$file" in
      *.md|*.yaml|*.yml|*.txt|*.sh|*.ps1) continue ;;
    esac

    [ -f "$blob" ] && [ -r "$blob" ] || staged_read_fail "copy failed for $file"
    count=$(grep -c 'TODO\|FIXME\|HACK\|XXX' < "$blob" || true)
    case "$count" in ''|*[!0-9]*) staged_read_fail "copy failed for $file" ;; esac
    if [ "$count" -gt 0 ]; then
      TODO_COUNT=$((TODO_COUNT + count))
    fi
  done

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
  if [[ "$STATE_DATA" =~ $PCC_RE_VALID ]] ||
     [[ "$LAST_VALIDATION_BLOCK" =~ $PCC_RE_PASS ]]; then
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
  if [[ "$CODE_REVIEW_BLOCK" =~ $PCC_RE_REQUIRED ]]; then
    if [[ "$CODE_REVIEW_BLOCK" =~ $PCC_RE_REVIEW_OK ]]; then
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
  if ( command -v pwsh ) >/dev/null 2>&1; then
    PS1_BAD=0
    PCC_REST="$STAGED_PS1"
    while [ -n "$PCC_REST" ]; do
      pcc_next_line
      f="$PCC_LINE"
      [ -z "$f" ] && continue
      [ -f "$PROJECT_ROOT/$f" ] || continue
      if ! pwsh -NoProfile -Command "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('$PROJECT_ROOT/$f', [ref]\$null, [ref]\$e) | Out-Null; if (\$e -and \$e.Count) { exit 1 } else { exit 0 }" >/dev/null 2>&1; then
        error "PowerShell parse error in staged $f"
        PS1_BAD=$((PS1_BAD+1))
      fi
    done
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
if [ -f "$DOC_NUMBER_GUARD" ] && ( command -v node ) >/dev/null 2>&1; then
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
if [ -f "$TRACKED_IGNORED_SCRIPT" ] && ( command -v node ) >/dev/null 2>&1; then
  TI_RC=0
  TI_OUT="$(node "$TRACKED_IGNORED_SCRIPT" --staged 2>&1)" || TI_RC=$?
  if [ "$TI_RC" -gt 1 ]; then
    warn "Gitignored-path check could not run (tracked-ignored.mjs exit $TI_RC) — skipped"
    echo "$TI_OUT" | sed 's/^/    /'
  else
    TI_SEEN=0
    TI_ADDED=0
    PCC_REST="$TI_OUT"
    while [ -n "$PCC_REST" ]; do
      pcc_next_line
      TI_LINE="$PCC_LINE"
      case "$TI_LINE" in
        "IGNORED_ADDED "*)
          TI_REST="${TI_LINE#IGNORED_ADDED }"
          TI_PATH="${TI_REST% rule=*}"; TI_RULE="${TI_REST##* rule=}"
          TI_SEEN=1
          TI_ADDED=1
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
    done
    if [ "$TI_RC" -eq 1 ] && [ "$TI_ADDED" -eq 0 ]; then
      # exit 1 is "an ADDED ignored path"; with no IGNORED_ADDED line the script
      # itself failed (e.g. an uncaught load error) and checked nothing.
      warn "Gitignored-path check could not run (tracked-ignored.mjs exit 1 without an IGNORED_ADDED line) — skipped"
      echo "$TI_OUT" | sed 's/^/    /'
    elif [ "$TI_SEEN" -eq 0 ]; then
      pass "No gitignored path staged"
    fi
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
