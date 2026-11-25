#!/usr/bin/env bash
# AAI:INDEX-AUTOGEN -- auto-regenerate docs/INDEX.md on docs/ changes.
# Installed by .aai/scripts/install-pre-commit-hook.sh or .ps1 from .aai/templates/git-hooks/.
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  exit 0
fi

# spec-precommit-residual-defects D2: staged name lists are read with -z and walked with
# read -d '', so a name git would C-quote (non-ASCII) is gated under its real path.
_aai_lists="$(mktemp -d "${TMPDIR:-/tmp}/aai-index-hook.XXXXXX")"
trap 'rm -rf "$_aai_lists"' EXIT
git diff --cached --name-only -z > "$_aai_lists/staged"
_has_docs=0
while IFS= read -r -d '' f; do case "$f" in docs/*) _has_docs=1; break ;; esac; done < "$_aai_lists/staged"
[[ "$_has_docs" == 1 ]] || exit 0

GEN=".aai/scripts/generate-docs-index.mjs"
if [[ ! -f "$GEN" ]]; then
  exit 0
fi

if ! node "$GEN"; then
  echo "AAI:INDEX-AUTOGEN: generator failed; commit aborted." >&2
  exit 1
fi

git add docs/INDEX.md
# Companion violations report is created when docs are malformed, removed when clean.
if [[ -f docs/INDEX.violations.md ]]; then
  git add docs/INDEX.violations.md
else
  git rm --cached --quiet --ignore-unmatch docs/INDEX.violations.md
fi
# SPEC-0010 / ISSUE-0003: docs/INDEX.audit.md carries git-history-dependent
# Orphans + Drift sections; it is git-ignored and must NEVER be staged (staging it
# would reintroduce the committed-index non-idempotence). Belt-and-suspenders un-stage.
git rm --cached --quiet --ignore-unmatch docs/INDEX.audit.md

# AAI:INDEX-AUTOGEN close-gate (SPEC-0011 G5): for each staged governed doc (a spec, or
# an intake doc under docs/issues, docs/rfc or docs/requirements) whose diff ADDS
# a 'status: done' frontmatter line, run the offline close gate. Block the commit
# only when docs/ai/docs-audit.yaml sets close_gate: enforce; otherwise warn and
# continue (report-only default -- absent config or close_gate: report-only never blocks).
# NOTE (CHANGE-0009 D8): the grep below is a deliberate THIN mirror of the guard
# dial; the CANONICAL reader of docs-audit.yaml is .aai/scripts/lib/guard-config.mjs
# (a conformance test asserts the grep pattern and the reader agree on fixtures).
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  # SPEC-0013 W1 (SPEC-0011-F2 class): the gate MODE must come from the config
  # that is actually being committed -- the STAGED blob when docs-audit.yaml is
  # staged, else HEAD -- never the worktree copy, whose UNSTAGED edit could
  # silently downgrade enforce -> warn. The worktree copy is the last resort
  # only when the config exists in neither the index nor HEAD (fresh repo).
  GATE_CFG="$(git show :docs/ai/docs-audit.yaml 2>/dev/null \
    || git show HEAD:docs/ai/docs-audit.yaml 2>/dev/null \
    || cat docs/ai/docs-audit.yaml 2>/dev/null \
    || true)"
  CLOSE_GATE_MODE="report-only"
  # Here-string, never printf piped into "grep -q" (round 10, PR #381).
  if grep -Eq $'^(\xef\xbb\xbf)?close_gate:[[:space:]]*enforce([[:space:]]|$)' <<<"$GATE_CFG"; then
    CLOSE_GATE_MODE="enforce"
  fi
  CLOSE_GATE_FAILED=0
  # issue-gate-via-spec D4: the governed doc directories that hold specs and
  # the intake docs close-work-item.mjs flips in the same close commit (a doc
  # with no AC table of its own gates through its linked spec inside
  # docs-audit.mjs). docs/releases/ is not gated: a release plan carries no
  # acceptance table and no spec links to it.
  git diff --cached --name-only -z --no-renames --diff-filter=ACM > "$_aai_lists/gated"
  # SPEC-0013 W2: newline-safe iteration -- an unquoted `for` word-splits paths
  # with spaces into nonexistent fragments whose failed `git show` silently
  # SKIPS the gate (the worst failure shape for a gate). D2: NUL-separated.
  while IFS= read -r -d '' f; do
    case "$f" in docs/issues/*.md|docs/rfc/*.md|docs/specs/*.md|docs/requirements/*.md) ;; *) continue ;; esac
    # only when the STAGED diff ADDS a 'status: done' line; with --no-renames a renamed doc counts as added,
    # so its 'status: done' line is an added line and a pure rename of a done doc is gated like a new doc
    # Capture, then here-string into grep -q (round 10, PR #381).
    _staged_hunk="$(git diff --cached --no-renames -U0 -- "$f")"
    if grep -Eq '^\+status:[[:space:]]*done([[:space:]]|$)' <<<"$_staged_hunk"; then
      # Gate the STAGED content, not the worktree: materialize the staged blob so a
      # staged-but-unreconciled done cannot pass merely because the worktree carries
      # unstaged Evidence (SPEC-0011 G5). Read the id from the staged blob too.
      STAGED_TMP="$(mktemp)"
      if ! git show ":$f" > "$STAGED_TMP" 2>/dev/null; then
        rm -f "$STAGED_TMP"
        continue
      fi
      # Capture, then here-string into head (round 10, PR #381).
      _staged_id_lines="$(sed -n 's/^id:[[:space:]]*//p' "$STAGED_TMP")"
      gid="$(head -1 <<<"$_staged_id_lines")"
      if [[ -z "$gid" ]]; then
        gid="$(basename "$f" .md | grep -oE '^[A-Z]+(-[A-Z]+)*-[0-9]+' || true)"
      fi
      if [[ -z "$gid" ]]; then
        rm -f "$STAGED_TMP"
        continue
      fi
      # --staged (hook-gate-staged-content D3): the linked specs this doc gates
      # through are read from the index too (HEAD when absent there), never
      # from the worktree. An older docs-audit.mjs ignores the flag.
      if GATE_OUT="$(node .aai/scripts/docs-audit.mjs --gate-file "$STAGED_TMP" --staged 2>&1)"; then
        :
      elif [[ "$CLOSE_GATE_MODE" == "enforce" ]]; then
        echo "AAI:INDEX-AUTOGEN close-gate: $gid fails the close gate (close_gate: enforce) -- commit aborted." >&2
        echo "$GATE_OUT" >&2
        CLOSE_GATE_FAILED=1
      else
        echo "AAI:INDEX-AUTOGEN close-gate WARNING: $gid fails the close gate (report-only; commit allowed)." >&2
        echo "$GATE_OUT" >&2
      fi
      rm -f "$STAGED_TMP"
    fi
  done < "$_aai_lists/gated"
  if [[ "$CLOSE_GATE_FAILED" == 1 ]]; then
    exit 1
  fi
fi

# AAI:INDEX-AUTOGEN body-lint (SPEC-0013 H1): for each STAGED governed docs/**/*.md
# file, materialize the STAGED blob (git show ":$f" -- LEARNED 2026-07-03: gate what
# is being committed, never the worktree copy) and body-lint it via
# docs-audit.mjs --lint-body-file. Block the commit only when docs/ai/docs-audit.yaml
# sets body_lint: enforce; otherwise warn and continue (report-only default,
# mirroring close_gate). Non-governed dirs (ai, knowledge, archive, _archive,
# project-sessions, templates, plans) and generated INDEX files are skipped.
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  # SPEC-0013 W1: same staged/HEAD-first config read as the close-gate block --
  # an unstaged worktree edit must not downgrade enforce -> warn.
  GATE_CFG="$(git show :docs/ai/docs-audit.yaml 2>/dev/null \
    || git show HEAD:docs/ai/docs-audit.yaml 2>/dev/null \
    || cat docs/ai/docs-audit.yaml 2>/dev/null \
    || true)"
  BODY_LINT_MODE="report-only"
  # Here-string, never printf piped into "grep -q" (round 10, PR #381).
  if grep -Eq $'^(\xef\xbb\xbf)?body_lint:[[:space:]]*enforce([[:space:]]|$)' <<<"$GATE_CFG"; then
    BODY_LINT_MODE="enforce"
  fi
  BODY_LINT_FAILED=0
  git diff --cached --name-only -z --no-renames --diff-filter=ACM > "$_aai_lists/linted"
  # SPEC-0013 W2: newline-safe iteration (see the close-gate loop above). D2: NUL-separated.
  while IFS= read -r -d '' f; do
    case "$f" in
      docs/ai/*|docs/knowledge/*|docs/archive/*|docs/_archive/*|docs/project-sessions/*|docs/templates/*|docs/plans/*|docs/INDEX*) continue ;;
      docs/*.md) ;; *) continue ;;
    esac
    STAGED_TMP="$(mktemp)"
    if ! git show ":$f" > "$STAGED_TMP" 2>/dev/null; then
      rm -f "$STAGED_TMP"
      continue
    fi
    if LINT_OUT="$(node .aai/scripts/docs-audit.mjs --lint-body-file "$STAGED_TMP" 2>&1)"; then
      :
    elif [[ "$BODY_LINT_MODE" == "enforce" ]]; then
      echo "AAI:INDEX-AUTOGEN body-lint: $f fails body lint (body_lint: enforce) -- commit aborted." >&2
      echo "$LINT_OUT" >&2
      BODY_LINT_FAILED=1
    else
      echo "AAI:INDEX-AUTOGEN body-lint WARNING: $f fails body lint (report-only; commit allowed)." >&2
      echo "$LINT_OUT" >&2
    fi
    rm -f "$STAGED_TMP"
  done < "$_aai_lists/linted"
  if [[ "$BODY_LINT_FAILED" == 1 ]]; then
    exit 1
  fi
fi
echo "AAI:INDEX-AUTOGEN: regenerated and staged docs/INDEX.md"
