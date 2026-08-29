#!/usr/bin/env bash
set -euo pipefail

# Install the AAI git hook SET into the EFFECTIVE hooks directory — the one
# `git rev-parse --git-path hooks/<name>` resolves, which honours core.hooksPath
# and a linked worktree's shared git dir. It is usually .git/hooks, but never
# assume that: see the resolve_hook_path comment below.
#   - pre-commit — opt-in, auto-regenerates docs/INDEX.md whenever
#     the commit touches docs/ (RFC-0001 layer 4 convenience).
#   - reference-transaction — refuses a refs/heads/main ref update
#     unless AAI_GIT_WRITE=1 is set on that exact command (D1/D3,
#     docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md). This
#     turns an honest/accidental write to main into a refusal instead of an
#     ambient default; it is not a security boundary (see the spec's D3).
#
# Usage:
#   ./.aai/scripts/install-pre-commit-hook.sh           # install if absent
#   ./.aai/scripts/install-pre-commit-hook.sh --force   # overwrite existing
#   ./.aai/scripts/install-pre-commit-hook.sh --uninstall
#   ./.aai/scripts/install-pre-commit-hook.sh --print   # emit the pre-commit
#                                                        # hook body to stdout
#                                                        # for a manual merge
#
# Idempotent per hook. Refuses to overwrite a non-AAI hook unless --force is
# given (checked for BOTH hooks before writing either, so a foreign hook in
# one slot never causes a partial install of the other).

FORCE=0
UNINSTALL=0
PRINT=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --print) PRINT=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unexpected argument: $arg" >&2
      exit 2
      ;;
  esac
done

# --print: emit the AAI:INDEX-AUTOGEN pre-commit hook body to stdout so a
# foreign-hook owner can hand-merge it, without touching any repo state.
# Extracted from this script's own heredoc (not a second copy) so it can
# never drift from what --force would actually install (PR #302 Copilot).
if [[ "$PRINT" == 1 ]]; then
  awk '/^cat > "\$HOOK_PATH" <<.HOOK.$/{p=1; next} /^HOOK$/{if(p){exit}} p' "$0"
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not inside a git repository." >&2
  exit 1
}
# Where git will ACTUALLY look for hooks.
#
# `git rev-parse --git-path hooks/<name>` is the resolution git itself performs
# to decide which file to execute, so it folds in BOTH things a hand-built path
# gets wrong:
#   - a linked worktree ships .git as a FILE, so a path built from
#     --show-toplevel never exists there (PR #302 Codex P2);
#   - `core.hooksPath` moves the hooks directory somewhere else entirely, and
#     --git-common-dir does not know about it (PR #304 Codex P1).
# The second one shipped a false success: reproduced in a scratch repo with
# core.hooksPath=.custom-hooks, this installer wrote .git/hooks/reference-
# transaction, exited 0, and a marker-less commit then moved refs/heads/main
# because git ran .custom-hooks/reference-transaction — which did not exist.
# aai-doctor CAT-17 already resolves the effective path this way; the installer
# now agrees with it instead of guessing.
#
# MEASURED (git 2.50.1), not assumed — the output is relative to the CURRENT
# DIRECTORY, not to the repo root, so it must be resolved against $PWD:
#   repo root,  hooksPath unset     -> .git/hooks/reference-transaction
#   repo root,  hooksPath=.custom   -> .custom/reference-transaction
#   repo root,  hooksPath absolute  -> /abs/path/reference-transaction
#   repo SUBDIR, hooksPath=.custom  -> ../../.custom/reference-transaction
#   linked worktree, unset          -> /abs/common/.git/hooks/reference-transaction
#   linked worktree, hooksPath=.c   -> .c/reference-transaction (per-worktree)
resolve_hook_path() {
  local name="$1" p
  p="$(git rev-parse --git-path "hooks/$name" 2>/dev/null)" || return 1
  [[ -n "$p" ]] || return 1
  [[ "$p" == /* ]] || p="$PWD/$p"
  printf '%s' "$p"
}

# A path we cannot resolve is a path we cannot install into safely, and a guard
# installed somewhere git never looks is worse than no guard at all — so this
# refuses loudly instead of exiting 0 on an inert hook.
HOOK_PATH="$(resolve_hook_path pre-commit)" || {
  echo "ERROR: could not resolve the effective git hooks path for pre-commit" >&2
  echo "       (git rev-parse --git-path failed). Refusing to install: a hook" >&2
  echo "       written to a guessed path would report success while git never runs it." >&2
  exit 1
}
REFTX_PATH="$(resolve_hook_path reference-transaction)" || {
  echo "ERROR: could not resolve the effective git hooks path for reference-transaction" >&2
  echo "       (git rev-parse --git-path failed). Refusing to install: a guard" >&2
  echo "       written to a guessed path would report success while git never runs it." >&2
  exit 1
}
HOOKS_DIR="$(dirname "$REFTX_PATH")"
MARKER="# AAI:INDEX-AUTOGEN"
REFTX_MARKER="# AAI:REF-GUARD"

# attest_effective <name> <marker> — re-ask git where it would look, and prove
# the file THERE is ours and runnable. This is the post-condition that makes
# the exit code mean something: exit 0 now asserts "git will run this", not
# merely "a write succeeded somewhere".
attest_effective() {
  local name="$1" marker="$2" p
  p="$(resolve_hook_path "$name")" || {
    echo "ERROR: installed $name but can no longer resolve the effective hooks path." >&2
    return 1
  }
  if [[ ! -f "$p" ]]; then
    echo "ERROR: git resolves the $name hook to $p, but no file is there." >&2
    return 1
  fi
  if ! grep -qF "$marker" "$p"; then
    echo "ERROR: the $name hook git would run ($p) does not carry $marker." >&2
    return 1
  fi
  if [[ ! -x "$p" ]]; then
    echo "ERROR: the $name hook git would run ($p) is not executable — git skips it silently." >&2
    return 1
  fi
  return 0
}

if [[ "$UNINSTALL" == 1 ]]; then
  if [[ -f "$HOOK_PATH" ]] && grep -qF "$MARKER" "$HOOK_PATH"; then
    rm "$HOOK_PATH"
    echo "Uninstalled AAI pre-commit hook from $HOOK_PATH"
  else
    echo "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
  fi
  if [[ -f "$REFTX_PATH" ]] && grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then
    rm "$REFTX_PATH"
    echo "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $REFTX_PATH"
  else
    echo "No AAI reference-transaction hook found (or hook is not AAI-managed). No action taken."
  fi
  exit 0
fi

FOREIGN=0
if [[ -f "$HOOK_PATH" && "$FORCE" != 1 ]] && ! grep -qF "$MARKER" "$HOOK_PATH"; then
  echo "ERROR: $HOOK_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the snippet manually:" >&2
  echo "       $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print" >&2
  FOREIGN=1
fi
if [[ -f "$REFTX_PATH" && "$FORCE" != 1 ]] && ! grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then
  echo "ERROR: $REFTX_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the AAI:REF-GUARD body manually." >&2
  FOREIGN=1
fi
if [[ "$FOREIGN" == 1 ]]; then
  exit 1
fi

if [[ -e "$HOOKS_DIR" && ! -d "$HOOKS_DIR" ]]; then
  echo "ERROR: the effective git hooks path $HOOKS_DIR exists and is not a directory." >&2
  echo "       Refusing to install rather than reporting success on a guard git cannot run." >&2
  exit 1
fi
mkdir -p "$HOOKS_DIR" || {
  echo "ERROR: could not create the effective git hooks directory $HOOKS_DIR." >&2
  exit 1
}

if [[ -f "$HOOK_PATH" && "$FORCE" != 1 ]] && grep -qF "$MARKER" "$HOOK_PATH"; then
  echo "AAI pre-commit hook already installed at $HOOK_PATH. No action taken."
else
cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
# AAI:INDEX-AUTOGEN — auto-regenerate docs/INDEX.md on docs/ changes.
# Installed by .aai/scripts/install-pre-commit-hook.sh
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  exit 0
fi

if ! git diff --cached --name-only | grep -qE '^docs/'; then
  exit 0
fi

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

# AAI:INDEX-AUTOGEN close-gate (SPEC-0011 G5): for each staged spec whose diff ADDS
# a 'status: done' frontmatter line, run the offline close gate. Block the commit
# only when docs/ai/docs-audit.yaml sets close_gate: enforce; otherwise warn and
# continue (report-only default — absent config or close_gate: report-only never blocks).
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  # SPEC-0013 W1 (SPEC-0011-F2 class): the gate MODE must come from the config
  # that is actually being committed — the STAGED blob when docs-audit.yaml is
  # staged, else HEAD — never the worktree copy, whose UNSTAGED edit could
  # silently downgrade enforce -> warn. The worktree copy is the last resort
  # only when the config exists in neither the index nor HEAD (fresh repo).
  GATE_CFG="$(git show :docs/ai/docs-audit.yaml 2>/dev/null \
    || git show HEAD:docs/ai/docs-audit.yaml 2>/dev/null \
    || cat docs/ai/docs-audit.yaml 2>/dev/null \
    || true)"
  CLOSE_GATE_MODE="report-only"
  if printf '%s\n' "$GATE_CFG" | grep -Eq '^close_gate:[[:space:]]*enforce([[:space:]]|$)'; then
    CLOSE_GATE_MODE="enforce"
  fi
  CLOSE_GATE_FAILED=0
  STAGED_SPECS="$(git diff --cached --name-only --diff-filter=ACM | grep -E '^docs/specs/.*\.md$' || true)"
  # SPEC-0013 W2: newline-safe iteration — an unquoted `for` word-splits paths
  # with spaces into nonexistent fragments whose failed `git show` silently
  # SKIPS the gate (the worst failure shape for a gate).
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # only when the STAGED diff ADDS a 'status: done' line (not an already-done spec)
    if git diff --cached -U0 -- "$f" | grep -Eq '^\+status:[[:space:]]*done([[:space:]]|$)'; then
      # Gate the STAGED content, not the worktree: materialize the staged blob so a
      # staged-but-unreconciled done cannot pass merely because the worktree carries
      # unstaged Evidence (SPEC-0011 G5). Read the id from the staged blob too.
      STAGED_TMP="$(mktemp)"
      if ! git show ":$f" > "$STAGED_TMP" 2>/dev/null; then
        rm -f "$STAGED_TMP"
        continue
      fi
      gid="$(sed -n 's/^id:[[:space:]]*//p' "$STAGED_TMP" | head -1)"
      if [[ -z "$gid" ]]; then
        gid="$(basename "$f" .md | grep -oE '^[A-Z]+(-[A-Z]+)*-[0-9]+' || true)"
      fi
      if [[ -z "$gid" ]]; then
        rm -f "$STAGED_TMP"
        continue
      fi
      if GATE_OUT="$(node .aai/scripts/docs-audit.mjs --gate-file "$STAGED_TMP" 2>&1)"; then
        :
      elif [[ "$CLOSE_GATE_MODE" == "enforce" ]]; then
        echo "AAI:INDEX-AUTOGEN close-gate: $gid fails the close gate (close_gate: enforce) — commit aborted." >&2
        echo "$GATE_OUT" >&2
        CLOSE_GATE_FAILED=1
      else
        echo "AAI:INDEX-AUTOGEN close-gate WARNING: $gid fails the close gate (report-only; commit allowed)." >&2
        echo "$GATE_OUT" >&2
      fi
      rm -f "$STAGED_TMP"
    fi
  done <<< "$STAGED_SPECS"
  if [[ "$CLOSE_GATE_FAILED" == 1 ]]; then
    exit 1
  fi
fi

# AAI:INDEX-AUTOGEN body-lint (SPEC-0013 H1): for each STAGED governed docs/**/*.md
# file, materialize the STAGED blob (git show ":$f" — LEARNED 2026-07-03: gate what
# is being committed, never the worktree copy) and body-lint it via
# docs-audit.mjs --lint-body-file. Block the commit only when docs/ai/docs-audit.yaml
# sets body_lint: enforce; otherwise warn and continue (report-only default,
# mirroring close_gate). Non-governed dirs (ai, knowledge, archive, _archive,
# project-sessions, templates, plans) and generated INDEX files are skipped.
if [[ -f .aai/scripts/docs-audit.mjs ]]; then
  # SPEC-0013 W1: same staged/HEAD-first config read as the close-gate block —
  # an unstaged worktree edit must not downgrade enforce -> warn.
  GATE_CFG="$(git show :docs/ai/docs-audit.yaml 2>/dev/null \
    || git show HEAD:docs/ai/docs-audit.yaml 2>/dev/null \
    || cat docs/ai/docs-audit.yaml 2>/dev/null \
    || true)"
  BODY_LINT_MODE="report-only"
  if printf '%s\n' "$GATE_CFG" | grep -Eq '^body_lint:[[:space:]]*enforce([[:space:]]|$)'; then
    BODY_LINT_MODE="enforce"
  fi
  BODY_LINT_FAILED=0
  STAGED_GOVERNED_DOCS="$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E '^docs/.*\.md$' \
    | grep -Ev '^docs/(ai|knowledge|archive|_archive|project-sessions|templates|plans)/' \
    | grep -Ev '^docs/INDEX' || true)"
  # SPEC-0013 W2: newline-safe iteration (see the close-gate loop above).
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    STAGED_TMP="$(mktemp)"
    if ! git show ":$f" > "$STAGED_TMP" 2>/dev/null; then
      rm -f "$STAGED_TMP"
      continue
    fi
    if LINT_OUT="$(node .aai/scripts/docs-audit.mjs --lint-body-file "$STAGED_TMP" 2>&1)"; then
      :
    elif [[ "$BODY_LINT_MODE" == "enforce" ]]; then
      echo "AAI:INDEX-AUTOGEN body-lint: $f fails body lint (body_lint: enforce) — commit aborted." >&2
      echo "$LINT_OUT" >&2
      BODY_LINT_FAILED=1
    else
      echo "AAI:INDEX-AUTOGEN body-lint WARNING: $f fails body lint (report-only; commit allowed)." >&2
      echo "$LINT_OUT" >&2
    fi
    rm -f "$STAGED_TMP"
  done <<< "$STAGED_GOVERNED_DOCS"
  if [[ "$BODY_LINT_FAILED" == 1 ]]; then
    exit 1
  fi
fi
echo "AAI:INDEX-AUTOGEN: regenerated and staged docs/INDEX.md"
HOOK
chmod +x "$HOOK_PATH"
echo "Installed AAI pre-commit hook at $HOOK_PATH"
echo "Effect: on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
fi

if [[ -f "$REFTX_PATH" && "$FORCE" != 1 ]] && grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then
  echo "AAI reference-transaction hook already installed at $REFTX_PATH. No action taken."
else
cat > "$REFTX_PATH" <<'REFTXHOOK'
#!/bin/sh
# AAI:REF-GUARD -- refuses a refs/heads/main ref update unless AAI_GIT_WRITE=1.
# Installed by .aai/scripts/install-pre-commit-hook.sh (or the .ps1 twin).
# This is a git reference-transaction hook: it fires for EVERY ref update in
# this repository, from any process, at any nesting depth, through any
# subshell. See
# docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md.

aai_state="$1"

if [ "$aai_state" != "prepared" ]; then
  exit 0
fi

aai_guarded=0
while read -r aai_old aai_new aai_ref; do
  if [ "$aai_ref" = "refs/heads/main" ]; then
    aai_guarded=1
  fi
done

if [ "$aai_guarded" != "1" ]; then
  exit 0
fi

if [ "$AAI_GIT_WRITE" = "1" ]; then
  exit 0
fi

cat >&2 <<'AAI_REF_GUARD_MSG'
AAI:REF-GUARD refused this refs/heads/main update.
  Guard:  git reference-transaction hook, marker AAI:REF-GUARD.
  Reason: a write to refs/heads/main must be a deliberate, narrow exception,
          never an ambient default (agent-shell-can-write-the-shipping-repo).
  Fix:    re-run this ONE command with AAI_GIT_WRITE=1 set, e.g.
            AAI_GIT_WRITE=1 git commit ...
  Uninstall this guard: bash .aai/scripts/install-pre-commit-hook.sh --uninstall
AAI_REF_GUARD_MSG
exit 1
REFTXHOOK
chmod +x "$REFTX_PATH"
echo "Installed AAI reference-transaction hook (AAI:REF-GUARD) at $REFTX_PATH"
echo "Effect: a refs/heads/main update is refused unless AAI_GIT_WRITE=1 is set on that command."
fi

# Post-condition (PR #304 Codex P1): exit 0 must mean "git will run these",
# never "a write succeeded somewhere". /aai-update reads this exit code as
# proof of protection, so a hook that landed off the effective path — or that
# lost its executable bit — has to end this script non-zero.
ATTEST_OK=1
attest_effective pre-commit "$MARKER" || ATTEST_OK=0
attest_effective reference-transaction "$REFTX_MARKER" || ATTEST_OK=0
if [[ "$ATTEST_OK" != 1 ]]; then
  echo "ERROR: installation did NOT leave an active hook at the path git resolves." >&2
  echo "       Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'." >&2
  exit 1
fi

echo "Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall"
