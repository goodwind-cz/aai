#!/usr/bin/env bash
set -euo pipefail

# Install the AAI git hook SET into the EFFECTIVE hooks directory — the one
# `git rev-parse --git-path hooks/<name>` resolves, which honours core.hooksPath
# and a linked worktree's shared git dir. It is usually .git/hooks, but never
# assume that: see the resolve_hook_path comment below. Three hooks, each
# recognised by its own marker:
#   - pre-commit (token index, marker AAI:INDEX-AUTOGEN) — auto-regenerates
#     docs/INDEX.md whenever the commit touches docs/ (RFC-0001 layer 4
#     convenience). Its first lines are a marker-scoped AAI:GUARD-CHECKS
#     block (`# AAI:GUARD-CHECKS BEGIN` … `END`) that runs
#     .aai/scripts/pre-commit-checks.sh on EVERY commit and refuses the
#     commit when that script does (secrets detection blocks; the doc-
#     numbering guard reports or blocks per docs/ai/docs-audit.yaml).
#   - reference-transaction (token ref-guard, marker AAI:REF-GUARD) — refuses
#     a refs/heads/main ref update unless AAI_GIT_WRITE=1 is set on that
#     exact command (D1/D3,
#     docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md).
#     This turns an honest/accidental write to main into a refusal instead
#     of an ambient default; it is not a security boundary (the spec's D3).
#   - pre-push (token close-gate, marker AAI:CLOSE-GATE) — runs
#     .aai/scripts/close-reconcile.mjs --check over every pushed range: a
#     default-branch ref is checked as <remote sha>..<local sha>, any other
#     ref as merge-base(origin/<default>, local)..local. Report-only unless
#     the PUSHED commit's docs/ai/docs-audit.yaml says `close_gate: enforce`,
#     and even then only a push to the default branch is refused
#     (docs/specs/SPEC-DRAFT-shipped-guards-have-no-downstream-trigger.md D1).
#
# Usage:
#   ./.aai/scripts/install-pre-commit-hook.sh           # install if absent
#   ./.aai/scripts/install-pre-commit-hook.sh --force   # overwrite existing
#   ./.aai/scripts/install-pre-commit-hook.sh --uninstall
#   ./.aai/scripts/install-pre-commit-hook.sh --print [index|ref-guard|guard-checks|pre-push]
#                                                        # emit a hook body (or
#                                                        # the guard block) to
#                                                        # stdout for a manual
#                                                        # merge (bare --print
#                                                        # keeps the index body)
#   ./.aai/scripts/install-pre-commit-hook.sh --print guard-checks
#                                                        # the AAI:GUARD-CHECKS
#                                                        # block alone
#   ./.aai/scripts/install-pre-commit-hook.sh --print pre-push
#                                                        # the AAI:CLOSE-GATE
#                                                        # pre-push body
#   ./.aai/scripts/install-pre-commit-hook.sh --hooks <csv>
#                                                        # select which hook(s)
#                                                        # to install/uninstall
#                                                        # -- closed set:
#                                                        # index, ref-guard, close-gate, all
#                                                        # (default all)
#   ./.aai/scripts/install-pre-commit-hook.sh --decline-ref-guard
#                                                        # remove the ref-guard
#                                                        # hook and record the
#                                                        # decline in
#                                                        # docs/ai/docs-audit.yaml
#   ./.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard
#                                                        # (re-)install the
#                                                        # ref-guard hook and
#                                                        # record the arm in
#                                                        # docs/ai/docs-audit.yaml
#
# Idempotent per hook. A plain run (no flags, the shape /aai-update runs after
# every successful sync) installs the SELECTED hooks that are absent, leaves
# an AAI-managed hook whose bytes already match alone, and honours a declared
# `ref_guard: declined` (docs/ai/docs-audit.yaml) by SKIPPING the ref-guard
# hook rather than silently re-arming it — so a plain run does not install
# "both hooks" on a repository that declined one; --arm-ref-guard or --force
# override the decline. It refuses to overwrite a non-AAI (foreign) hook in a
# selected slot unless --force is given, and checks EVERY selected slot before
# writing any, so a foreign hook in one slot never causes a partial install.
# An AAI pre-commit hook installed before the guard block existed is UPGRADED
# in place: the block is inserted after the shebang line and every other byte
# is left as it was (a hand-merged foreign hook that adopted the marker keeps
# its own body); a hook the installer cannot prove it owns — no AAI marker, a
# symlinked slot, a CR-terminated first line, more than one guard block — is
# refused by name and left byte-identical. Nothing outside an AAI marker is
# ever deleted or rewritten by a plain run.

FORCE=0
UNINSTALL=0
PRINT=0
PRINT_HOOK=""
HOOKS_ARG="all"
HOOKS_ARG_EXPLICIT=0
DECLINE_REF_GUARD=0
ARM_REF_GUARD=0

# Index-based (not `for arg in "$@"`) so --hooks and an optional --print
# argument can each consume the NEXT token — Spec-AC-01/Spec-AC-03.
_ARGV=("$@")
_ARGC=${#_ARGV[@]}
_i=0
while [[ $_i -lt $_ARGC ]]; do
  arg="${_ARGV[$_i]}"
  case "$arg" in
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --decline-ref-guard) DECLINE_REF_GUARD=1 ;;
    --arm-ref-guard) ARM_REF_GUARD=1 ;;
    --print)
      PRINT=1
      # --print's hook argument is OPTIONAL: only a literal 'index',
      # 'ref-guard', 'guard-checks' or 'pre-push' immediately after it is
      # consumed, so `--print --force` still parses --force as its own flag
      # (bare --print stays valid).
      if [[ $((_i + 1)) -lt $_ARGC ]]; then
        case "${_ARGV[$((_i + 1))]}" in
          index|ref-guard|guard-checks|pre-push)
            PRINT_HOOK="${_ARGV[$((_i + 1))]}"
            _i=$((_i + 1))
            ;;
        esac
      fi
      ;;
    --hooks)
      _i=$((_i + 1))
      if [[ $_i -ge $_ARGC ]]; then
        echo "ERROR: --hooks requires a value (closed set: index, ref-guard, close-gate, all)" >&2
        exit 2
      fi
      HOOKS_ARG="${_ARGV[$_i]}"
      HOOKS_ARG_EXPLICIT=1
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unexpected argument: $arg" >&2
      exit 2
      ;;
  esac
  _i=$((_i + 1))
done

# --hooks is contradictory with --decline-ref-guard/--arm-ref-guard (frozen
# Implementation plan edge case, undisclosed deviation flagged by code
# review 20260924T124304Z D-1: measured, --decline-ref-guard --hooks
# ref-guard used to exit 0 silently ignoring --hooks). Both single-purpose
# actions act on the reference-transaction hook alone and dispatch-and-exit
# BEFORE the --hooks-selected flow below is ever reached, so a --hooks value
# on the same command line can never do anything — exit 2 naming the
# contradiction rather than silently accept and ignore it. Checked against
# EXPLICIT use only (HOOKS_ARG_EXPLICIT), so a bare --decline-ref-guard
# (HOOKS_ARG's unconsulted "all" default) is unaffected. TEST-645.
if [[ ( "$DECLINE_REF_GUARD" == 1 || "$ARM_REF_GUARD" == 1 ) && "$HOOKS_ARG_EXPLICIT" == 1 ]]; then
  echo "ERROR: --hooks is contradictory with --decline-ref-guard/--arm-ref-guard (these act on the reference-transaction hook alone)." >&2
  exit 2
fi

# --hooks <csv> over the closed set index/ref-guard/close-gate/all (D6; the
# close-gate token added by shipped-guards-have-no-downstream-trigger D7),
# default all — resolved once into the three booleans every selection-aware
# guard below consults. An unknown token exits 2 naming the closed set and
# writes nothing (checked before any repo/hook state is touched).
#
# --hooks "" (validation round 1, N2): an empty string is not a member of the
# closed set either, but the csv loop below only iterates while the remainder
# is non-empty, so an empty HOOKS_ARG used to fall straight through with both
# booleans still 0 -- exit 0, nothing installed, the success footer printed
# anyway. The .ps1 twin already rejected it (its foreach over -split ','
# yields one empty token, which hits its own closed-set default branch).
# Rejected here explicitly so the twins agree.
if [[ -z "$HOOKS_ARG" ]]; then
  echo "ERROR: unknown --hooks value: '' (closed set: index, ref-guard, close-gate, all)" >&2
  exit 2
fi
WANT_INDEX=0
WANT_REFGUARD=0
WANT_CLOSEGATE=0
_hooks_csv="$HOOKS_ARG"
while [[ -n "$_hooks_csv" ]]; do
  _hooks_tok="${_hooks_csv%%,*}"
  case "$_hooks_csv" in
    *,*) _hooks_csv="${_hooks_csv#*,}" ;;
    *) _hooks_csv="" ;;
  esac
  case "$_hooks_tok" in
    index) WANT_INDEX=1 ;;
    ref-guard) WANT_REFGUARD=1 ;;
    close-gate) WANT_CLOSEGATE=1 ;;
    all) WANT_INDEX=1; WANT_REFGUARD=1; WANT_CLOSEGATE=1 ;;
    *)
      echo "ERROR: unknown --hooks value: '$_hooks_tok' (closed set: index, ref-guard, close-gate, all)" >&2
      exit 2
      ;;
  esac
done

# --print [index|ref-guard|guard-checks|pre-push]: emit a hook body (or the
# guard block) to stdout so a foreign-hook owner can hand-merge it, without
# touching any repo state. Bare --print (or --print index) keeps emitting the
# AAI:INDEX-AUTOGEN body (TEST-314 muscle memory, D5); --print ref-guard
# emits the AAI:REF-GUARD body; --print guard-checks the AAI:GUARD-CHECKS
# block a fresh pre-commit install embeds at its top; --print pre-push the
# AAI:CLOSE-GATE body. Every one is extracted from this script's own heredoc
# (never a second copy) so none can drift from what --hooks would actually
# install (PR #302 Copilot; D5).
if [[ "$PRINT" == 1 ]]; then
  case "$PRINT_HOOK" in
    ref-guard)
      awk '/^if ! cat > "\$REFTX_PATH" <<.REFTXHOOK.$/{p=1; next} /^REFTXHOOK$/{if(p){exit}} p' "$0"
      ;;
    guard-checks)
      awk '/^cat <<.GUARDBLOCK.$/{p=1; next} /^GUARDBLOCK$/{if(p){exit}} p' "$0"
      ;;
    pre-push)
      awk '/^cat <<.PREPUSHHOOK.$/{p=1; next} /^PREPUSHHOOK$/{if(p){exit}} p' "$0"
      ;;
    *)
      awk '/^cat <<.HOOK.$/{p=1; next} /^HOOK$/{if(p){exit}} p' "$0"
      ;;
  esac
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
PREPUSH_PATH="$(resolve_hook_path pre-push)" || {
  echo "ERROR: could not resolve the effective git hooks path for pre-push" >&2
  echo "       (git rev-parse --git-path failed). Refusing to install: a guard" >&2
  echo "       written to a guessed path would report success while git never runs it." >&2
  exit 1
}
HOOKS_DIR="$(dirname "$REFTX_PATH")"
MARKER="# AAI:INDEX-AUTOGEN"
REFTX_MARKER="# AAI:REF-GUARD"
PREPUSH_MARKER="# AAI:CLOSE-GATE"
GUARD_BLOCK_BEGIN="# AAI:GUARD-CHECKS BEGIN"
GUARD_BLOCK_END="# AAI:GUARD-CHECKS END"

# has_marker_line <file> <marker> — the ownership test for the three hook
# markers (INDEX-AUTOGEN, REF-GUARD, CLOSE-GATE). The marker must OPEN a
# line: column 0, followed by a space, end of line, or a CR (a CRLF hook the
# .ps1 twin wrote on Windows) — the shape every shipped body carries
# ("# AAI:INDEX-AUTOGEN — auto-regenerate …"). A substring hit is NOT
# ownership: a foreign hook whose comment merely mentions the marker, or
# quotes it inside a string, must not be upgraded into and must never be
# deleted by --uninstall (validation NB3; the #414 class). Exact whole-line
# matching — what the GUARD-CHECKS markers use — is not available here: the
# shipped bodies themselves carry commentary after the marker on that line
# and their bytes are pinned (PRECOMMIT_SHA256_BASELINE). The .ps1 twin's
# Find-MarkerLines applies the identical rule on bytes.
has_marker_line() {
  local cr=$'\r'
  grep -qE "^$2( |$cr?\$)" "$1"
}
# docs/ai/docs-audit.yaml — the committed guard-policy surface (D2). Read by
# lib/guard-config.mjs's readRefGuardPolicy (the canonical JS reader) and
# mirrored here by a deliberate THIN shell grep (no node import in this
# script — check-vendored-script-deps.mjs gates it); the conformance test is
# tests/skills/test-aai-hygiene-pack.sh test_618 (Spec-AC-06).
CONFIG_PATH="$REPO_ROOT/docs/ai/docs-audit.yaml"

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
  if ! has_marker_line "$p" "$marker"; then
    echo "ERROR: the $name hook git would run ($p) does not carry $marker." >&2
    return 1
  fi
  if [[ ! -x "$p" ]]; then
    echo "ERROR: the $name hook git would run ($p) is not executable — git skips it silently." >&2
    return 1
  fi
  return 0
}

# foreign_reftx_refusal — the shared refusal text for a foreign (non-AAI)
# file occupying the reference-transaction slot: Spec-AC-03/D5's own
# --print ref-guard command is the ONE place this sentence is spelled out, so
# arm_ref_guard (Spec-AC-05) reuses it verbatim rather than carrying a second,
# driftable copy (a second copy is exactly what broke TEST-612's mutation
# target the first time this function was written — see the commit).
foreign_reftx_refusal() {
  echo "ERROR: $REFTX_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the AAI:REF-GUARD body with: $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print ref-guard" >&2
}

# foreign_prepush_refusal — the pre-push slot's twin of the above (the
# reference-transaction slot's contract, SPEC-0184 Spec-AC-02, applied to the
# third slot): one function, one sentence, naming --print pre-push.
foreign_prepush_refusal() {
  echo "ERROR: $PREPUSH_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the AAI:CLOSE-GATE body with: $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print pre-push" >&2
}

# ensure_hooks_dir — create or validate the EFFECTIVE git hooks directory
# (dirname of $REFTX_PATH) before anything writes into it. Both the normal
# --hooks write path below and the explicit --arm-ref-guard/--decline-ref-guard
# dispatch (Spec-AC-05) call this before touching $REFTX_PATH: `core.hooksPath`
# can point at a directory that does not exist yet (measured: a scratch repo
# with `git config core.hooksPath nonexistent-dir`), and a write into a missing
# directory must be refused, not silently skipped and reported installed.
ensure_hooks_dir() {
  if [[ -e "$HOOKS_DIR" && ! -d "$HOOKS_DIR" ]]; then
    echo "ERROR: the effective git hooks path $HOOKS_DIR exists and is not a directory." >&2
    echo "       Refusing to install rather than reporting success on a guard git cannot run." >&2
    return 1
  fi
  mkdir -p "$HOOKS_DIR" || {
    echo "ERROR: could not create the effective git hooks directory $HOOKS_DIR." >&2
    return 1
  }
}

# write_refguard_hook — install the AAI:REF-GUARD reference-transaction hook
# body (skip, reporting so, when it is already AAI-managed and --force is not
# given). Shared by the normal --hooks ref-guard write path below AND
# arm_ref_guard (Spec-AC-05), so the heredoc's bytes live in exactly ONE
# place — D9: no byte of the installed hook body may drift between callers.
# CALLERS MUST ensure_hooks_dir first: this function does not create
# $HOOKS_DIR itself, and every branch below is guarded so the final "Installed"
# line cannot print unless the write it describes actually happened (TEST-647:
# a missing $HOOKS_DIR used to leave `cat`/`chmod` silently failing under the
# `arm_ref_guard || exit 1` call — set -e does not fire for a command whose
# exit status is being tested — while this function's last command, the echo,
# still ran and reported success on nothing written).
write_refguard_hook() {
  if [[ -f "$REFTX_PATH" && "$FORCE" != 1 ]] && has_marker_line "$REFTX_PATH" "$REFTX_MARKER"; then
    echo "AAI reference-transaction hook already installed at $REFTX_PATH. No action taken."
    return 0
  fi
if ! cat > "$REFTX_PATH" <<'REFTXHOOK'
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
then
    echo "ERROR: could not write $REFTX_PATH (TEST-647: the effective hooks directory may be missing)." >&2
    return 1
  fi
  if ! chmod +x "$REFTX_PATH"; then
    echo "ERROR: could not make $REFTX_PATH executable." >&2
    return 1
  fi
  echo "Installed AAI reference-transaction hook (AAI:REF-GUARD) at $REFTX_PATH"
  echo "Effect: a refs/heads/main update is refused unless AAI_GIT_WRITE=1 is set on that command. Decline: bash $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --decline-ref-guard"
}

# read_ref_guard_policy <config-path> — thin column-0 shell MIRROR of
# lib/guard-config.mjs's readRefGuardPolicy (Spec-AC-06/D3; conformance-tested
# on a shared fixture set by tests/skills/test-aai-hygiene-pack.sh test_618,
# the same discipline test_031 already applies to the enforce/report-only
# dials). FAILS CLOSED, like the JS reader: prints 'declined' only for a
# literal column-0 `ref_guard: declined` line; an absent file, an absent key,
# an indented or commented key, or any OTHER value (including 'armed')
# prints 'armed'. write_ref_guard_policy below uses it as its own post-write
# attestation — the same "exit 0 must mean it really happened" discipline
# attest_effective applies to the installed hooks.
read_ref_guard_policy() {
  local cfg="$1"
  if [[ -f "$cfg" ]] && grep -Eq '^ref_guard:[[:space:]]*declined([[:space:]]|$)' "$cfg" 2>/dev/null; then
    printf 'declined'
  else
    printf 'armed'
  fi
}

# write_ref_guard_policy <armed|declined> — replace-or-append the column-0
# `ref_guard: <value>` line in docs/ai/docs-audit.yaml (D2), creating the file
# with only this key when it is absent, and disturbing no other key or
# comment. "Replace" recognises ANY column-0 `ref_guard:` line carrying a
# non-blank token as the key to replace — the SAME "is this line the key"
# grammar lib/guard-config.mjs's readRefGuardPolicy uses (Spec-AC-06's
# `^ref_guard:\s*(\S+)`), not the narrower armed|declined set an earlier
# version of this gate used. Idempotent per Spec-AC-05: writing the SAME
# value twice leaves the file byte-identical, because the valid line just
# written matches on the next pass. Ends by reading the value back through
# read_ref_guard_policy above and refusing if it disagrees — the write is
# not trusted merely because it did not error.
#
# WHY "any token", not a closed set (validation round 2, B2): the earlier
# gate matched ONLY an existing armed|declined line, so a config already
# carrying an out-of-vocabulary `ref_guard:` value (a typo) was never
# recognised as replaceable — it fell to the APPEND branch below and the file
# ended up with TWO `ref_guard:` lines. `--arm-ref-guard` then violated
# Spec-AC-05's "leaving exactly one ref_guard: line" outright (measured:
# `grep -c` == 2). In the decline direction the canonical JS reader
# (first-occurrence-wins) kept reading the STALE first line while this
# script's own read_ref_guard_policy mirror (a whole-file search) found the
# freshly appended second line — the two readers disagreed about a file THIS
# script had just written, and because the plain-install skip below now
# consults that same mirror (N1), the disagreement reached a consumer as a
# silent, permanent disarm: ISSUE-0083's complaint, restored through a
# success path. Of the three fix shapes validation named, the other two were
# rejected: refusing an unrecognised existing value outright would block the
# very command a consumer runs BECAUSE the value is wrong, trading the
# one-command exit D2 promises for a forced manual edit; and widening only
# the post-write read-back would turn the violation into a loud failure
# rather than the SUCCESS Spec-AC-05 requires ("SHALL ... leaving exactly one
# ref_guard: line") — a failed run does not satisfy a SHALL either. Widening
# the gate instead makes `--arm-ref-guard` / `--decline-ref-guard`
# self-healing: an explicit arm/decline command corrects a stray value in
# place instead of shadowing it behind a second line.
#
# CRLF (validation round 1, B1; round 2, NB1): the GATE grep and the ACTION
# awk below now use the IDENTICAL character class, [[:space:]], in both —
# not merely overlapping ones. An earlier fix widened the awk to [ \t\r] to
# match most of the grep's [[:space:]], but \v and \f stayed gate-only, so
# the original CRLF-class bug survived on those two bytes (round 2 measured
# it: a config with `ref_guard:\x0Barmed` still split the gate from the
# action). Spelling both sides as [[:space:]] — this awk program, and every
# other POSIX-conforming awk, accepts POSIX bracket classes — leaves exactly
# one whitespace definition in this function instead of two kept in sync by
# hand, so the class cannot re-drift. This file is project-owned and CRLF is
# a legitimate shape for it (D2), so the fix stays matcher parity, not a
# rewrite of bytes the consumer did not ask this script to touch.
# lib/guard-config.mjs's readRefGuardPolicy never had the CRLF class bug — it
# splits on /\r?\n/, which consumes a trailing CR as part of the line
# delimiter — and the .ps1 twin reads lines with Get-Content, which strips
# every line-ending style before any regex runs.
# CREATION (code review 20260924T124304Z B2): the mere EXISTENCE of
# docs/ai/docs-audit.yaml flips docs-audit from report-only to enforced mode
# (lib/docs-audit-core.mjs loadConfig/runAudit — any parsed config, however
# sparse, makes `mode = 'enforced'`; measured: docs-audit --check rc 0->1 in
# a scratch repo with one schema-violating doc, purely from this file coming
# into existence). aai-sync.sh already creates this same file and already
# discloses that exact consequence ("SEED docs/ai/docs-audit.yaml from
# .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit
# --check now runs enforced)"); a --decline-ref-guard or --arm-ref-guard run
# that creates the file silently was a second, undisclosed creation path for
# the ride whose own thesis is "a consumer learns what a command is about to
# change". Fixed the stronger way the reviewer offered: SEED from the same
# template aai-sync uses (so the file this command creates is the same
# object a sync would have created — every OTHER dial report-only, not a
# bare single-key stub) and print the SAME disclosure line, before setting
# the ref_guard key on top. When the template is not present (a pre-CHANGE-
# 0121 vendored tree), fall back to a bare NOTE naming the same consequence
# — never create the file silently either way. This governs ONLY the first
# write to an absent file; a second run down either branch takes the
# existing "replace" gate above and is unaffected.
write_ref_guard_policy() {
  local value="$1" write_mode="replace_or_append_key"
  local config_was_absent=0
  [[ -f "$CONFIG_PATH" ]] || config_was_absent=1
  mkdir -p "$(dirname "$CONFIG_PATH")"
  if [[ "$write_mode" == "replace_or_append_key" ]] && [[ -f "$CONFIG_PATH" ]] \
     && grep -Eq '^ref_guard:[[:space:]]*[^[:space:]]' "$CONFIG_PATH" 2>/dev/null; then
    local tmp; tmp="$(mktemp)"
    awk -v val="$value" '
      /^ref_guard:[[:space:]]*[^[:space:]]/ && !done { print "ref_guard: " val; done=1; next }
      { print }
    ' "$CONFIG_PATH" > "$tmp"
    mv "$tmp" "$CONFIG_PATH"
  else
    if [[ "$config_was_absent" == 1 ]]; then
      local docs_audit_template="$REPO_ROOT/.aai/templates/docs-audit.template.yaml"
      if [[ -f "$docs_audit_template" ]]; then
        cp -a "$docs_audit_template" "$CONFIG_PATH"
        echo "SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit --check now runs enforced)"
      else
        echo "NOTE: creating docs/ai/docs-audit.yaml -- this switches docs-audit from report-only to enforced mode (docs-audit --check may now hard-fail on pre-existing orphans/violations it previously only reported)."
      fi
    fi
    if [[ -f "$CONFIG_PATH" && -s "$CONFIG_PATH" ]]; then
      local last_byte; last_byte="$(tail -c1 "$CONFIG_PATH" 2>/dev/null)"
      [[ -n "$last_byte" ]] && printf '\n' >> "$CONFIG_PATH"
    fi
    printf 'ref_guard: %s\n' "$value" >> "$CONFIG_PATH"
  fi
  local verify; verify="$(read_ref_guard_policy "$CONFIG_PATH")"
  if [[ "$verify" != "$value" ]]; then
    echo "ERROR: wrote ref_guard: $value to $CONFIG_PATH but reading it back gives $verify." >&2
    return 1
  fi
}

# decline_ref_guard — Spec-AC-05: remove an AAI-managed ref-guard hook if
# present, refuse (unmodified) a foreign one, and record ref_guard: declined.
#
# ORDER (validation round 1, B1b): write the declaration BEFORE removing the
# hook. The D6 discipline this file already applies to the hook slots ("check
# both before writing either") is extended here to the decline's own two
# effects: a write_ref_guard_policy failure (an unwritable config -- read-only
# fs, permissions) must never leave the guard removed with no record of why.
# Writing first means that failure returns 1 with the guard still installed
# and still armed -- disarmed-but-silent was never reachable, not merely rare.
# arm_ref_guard does not need the same reorder: D4 makes CAT-17 (and every
# other reader) trust an actually-installed hook file over the declaration,
# so a stale 'declined' line surviving a hook install that then fails to
# record 'armed' is read as armed anyway, by design.
decline_ref_guard() {
  local reftx_is_aai=0
  [[ -f "$REFTX_PATH" ]] && has_marker_line "$REFTX_PATH" "$REFTX_MARKER" && reftx_is_aai=1  # AC-05 decline removal: foreign-marker test
  if [[ -f "$REFTX_PATH" && "$reftx_is_aai" != 1 ]]; then
    echo "ERROR: $REFTX_PATH already exists and is not AAI-managed." >&2
    echo "       Refusing to remove a foreign hook -- --decline-ref-guard only removes an AAI-managed guard." >&2
    return 1
  fi
  write_ref_guard_policy declined || return 1
  if [[ -f "$REFTX_PATH" ]]; then
    rm "$REFTX_PATH"
    echo "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $REFTX_PATH"
  fi
  echo "Declined the AAI reference-transaction guard. Recorded ref_guard: declined in $CONFIG_PATH"
  echo "Re-arm with: bash $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard"
}

# arm_ref_guard — Spec-AC-05: (re-)install the ref-guard hook (same
# foreign-hook refusal as the normal write path) and record ref_guard: armed.
arm_ref_guard() {
  if [[ -f "$REFTX_PATH" && "$FORCE" != 1 ]] && ! has_marker_line "$REFTX_PATH" "$REFTX_MARKER"; then
    foreign_reftx_refusal
    return 1
  fi
  ensure_hooks_dir || return 1  # TEST-647: core.hooksPath may name a directory that does not exist yet
  write_refguard_hook || return 1
  attest_effective reference-transaction "$REFTX_MARKER" || return 1
  write_ref_guard_policy armed || return 1
  echo "Recorded ref_guard: armed in $CONFIG_PATH"
}

# guard_block_body — the AAI:GUARD-CHECKS block a fresh pre-commit install
# embeds right after its shebang, and the block an UPGRADE inserts into a
# pre-existing AAI hook (upgrade_precommit_hook below). It runs
# .aai/scripts/pre-commit-checks.sh from the repo root BEFORE the index
# body's early `exit 0` (which fires on every commit that touches nothing
# under docs/), propagates a non-zero rc as a refused commit, and degrades
# to a named NOTE when the script is absent. Everything between the two
# marker lines is engine-owned and is the ONLY range an upgrade ever
# rewrites; `--print guard-checks` extracts these same bytes from this
# heredoc (never a second copy), so the printed block cannot drift from the
# installed one (SPEC-DRAFT-shipped-guards-have-no-downstream-trigger D6).
guard_block_body() {
cat <<'GUARDBLOCK'
# AAI:GUARD-CHECKS BEGIN
# managed by install-pre-commit-hook; edit outside these markers
# Runs .aai/scripts/pre-commit-checks.sh (secrets detection blocks; the
# doc-numbering guard reports or blocks per docs/ai/docs-audit.yaml) on
# every commit, before the AAI:INDEX-AUTOGEN body below.
_gc_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_gc_script="$_gc_root/.aai/scripts/pre-commit-checks.sh"
if [ -f "$_gc_script" ]; then
  echo "AAI:GUARD-CHECKS: running .aai/scripts/pre-commit-checks.sh"
  _gc_rc=0
  bash "$_gc_script" || _gc_rc=$?
  if [ "$_gc_rc" -ne 0 ]; then
    echo "AAI:GUARD-CHECKS: pre-commit-checks.sh blocked this commit (rc=$_gc_rc)" >&2
    exit "$_gc_rc"
  fi
else
  echo "AAI:GUARD-CHECKS NOTE: .aai/scripts/pre-commit-checks.sh absent; guard checks skipped" >&2
fi
# AAI:GUARD-CHECKS END
GUARDBLOCK
}

# index_hook_body — the AAI:INDEX-AUTOGEN pre-commit body as shipped before
# the guard block existed (bare `--print` / `--print index` emit exactly these
# bytes, TEST-314 muscle memory). A FRESH install composes the hook as
# <this body's shebang line> + guard_block_body + <the rest of this body>;
# an UPGRADE of a hook that already carries this body inserts only the block.
index_hook_body() {
cat <<'HOOK'
#!/usr/bin/env bash
# AAI:INDEX-AUTOGEN — auto-regenerate docs/INDEX.md on docs/ changes.
# Installed by .aai/scripts/install-pre-commit-hook.sh
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  exit 0
fi

# Capture, then here-string into grep -q — never a live pipe into an
# early-closing reader under pipefail (round 10, PR #381).
_staged_names="$(git diff --cached --name-only)"
if ! grep -qE '^docs/' <<<"$_staged_names"; then
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
  # Here-string, never printf piped into "grep -q" (round 10, PR #381).
  if grep -Eq '^close_gate:[[:space:]]*enforce([[:space:]]|$)' <<<"$GATE_CFG"; then
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
    # Capture, then here-string into grep -q (round 10, PR #381).
    _staged_hunk="$(git diff --cached -U0 -- "$f")"
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
  # Here-string, never printf piped into "grep -q" (round 10, PR #381).
  if grep -Eq '^body_lint:[[:space:]]*enforce([[:space:]]|$)' <<<"$GATE_CFG"; then
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
}

# pre_push_body — the AAI:CLOSE-GATE pre-push hook: one close-reconcile.mjs
# --check per pushed ref (D1). Git feeds `<local ref> <local sha> <remote ref>
# <remote sha>` per line on stdin and the remote name as $1.
pre_push_body() {
cat <<'PREPUSHHOOK'
#!/usr/bin/env bash
# AAI:CLOSE-GATE -- runs close-reconcile.mjs --check over every pushed range.
# Installed by .aai/scripts/install-pre-commit-hook.sh (or the .ps1 twin).
# Per pushed ref (stdin: <local ref> <local sha> <remote ref> <remote sha>):
#   - a deletion (all-zero local sha) is skipped;
#   - the default branch (refs/remotes/origin/HEAD, else main) is checked as
#     <remote sha>..<local sha>; a first push (all-zero remote sha) as
#     <local sha>^..<local sha> -- the rule .github/workflows/close-gate.yml
#     applies;
#   - any other ref as merge-base(refs/remotes/<remote>/<default>, local)..local.
# Verdict: `close_gate` read from the PUSHED commit's docs/ai/docs-audit.yaml
# (never the worktree copy). report-only (default): print, exit 0. enforce:
# refuse ONLY a push to the default branch; every other ref stays report-
# only, because WIP pushes legitimately precede the close ceremony.
# See docs/specs/SPEC-DRAFT-shipped-guards-have-no-downstream-trigger.md.

_cg_remote="${1:-origin}"
_cg_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_cg_script="$_cg_root/.aai/scripts/close-reconcile.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "AAI:CLOSE-GATE NOTE: node not found; close gate skipped" >&2
  exit 0
fi
if [ ! -f "$_cg_script" ]; then
  echo "AAI:CLOSE-GATE NOTE: $_cg_script absent; close gate skipped" >&2
  exit 0
fi

# R1 -- default branch: refs/remotes/origin/HEAD with the origin/ prefix
# stripped; else main, and say so.
_cg_default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
_cg_default="${_cg_default#origin/}"
if [ -z "$_cg_default" ]; then
  _cg_default="main"
  echo "AAI:CLOSE-GATE NOTE: default branch assumed main (refs/remotes/origin/HEAD unset)" >&2
fi
echo "AAI:CLOSE-GATE: default branch $_cg_default (remote $_cg_remote)"

_cg_refused=0
while read -r _cg_lref _cg_local _cg_rref _cg_remote_sha; do
  [ -n "$_cg_lref" ] || continue
  case "$_cg_local" in
    *[!0]*) ;;
    *) echo "AAI:CLOSE-GATE: $_cg_rref is a deletion; nothing to check"; continue ;;
  esac
  # The dial, read from what is being PUSHED (the same "gate what ships,
  # never the worktree copy" discipline the pre-commit body applies).
  _cg_mode="report-only"
  _cg_cfg="$(git show "$_cg_local:docs/ai/docs-audit.yaml" 2>/dev/null || true)"
  if grep -Eq '^close_gate:[[:space:]]*enforce([[:space:]]|$)' <<<"$_cg_cfg"; then
    _cg_mode="enforce"
  fi
  _cg_is_default=0
  if [ "$_cg_rref" = "refs/heads/$_cg_default" ]; then
    _cg_is_default=1
  fi
  if [ "$_cg_is_default" = 1 ]; then
    case "$_cg_remote_sha" in
      *[!0]*) _cg_range="$_cg_remote_sha..$_cg_local" ;;
      *) _cg_range="$_cg_local^..$_cg_local" ;;
    esac
  else
    _cg_base="$(git merge-base "refs/remotes/$_cg_remote/$_cg_default" "$_cg_local" 2>/dev/null || true)"
    if [ -z "$_cg_base" ]; then
      echo "AAI:CLOSE-GATE NOTE: $_cg_rref skipped -- refs/remotes/$_cg_remote/$_cg_default unresolvable" >&2
      continue
    fi
    _cg_range="$_cg_base..$_cg_local"
  fi
  echo "AAI:CLOSE-GATE: $_cg_rref range=$_cg_range close_gate=$_cg_mode"
  _cg_rc=0
  _cg_out="$(node "$_cg_script" --check --range "$_cg_range" --root "$_cg_root" 2>&1)" || _cg_rc=$?
  printf '%s\n' "$_cg_out"
  if [ "$_cg_rc" -eq 0 ]; then
    continue
  fi
  if [ "$_cg_rc" -eq 2 ]; then
    echo "AAI:CLOSE-GATE NOTE: close-reconcile.mjs could not resolve range $_cg_range (rc=2)" >&2
  fi
  if [ "$_cg_mode" = "enforce" ] && [ "$_cg_is_default" = 1 ]; then
    echo "AAI:CLOSE-GATE refused: push of $_cg_rref (close_gate: enforce, default branch $_cg_default) -- the close ceremony did not run for range $_cg_range (rc=$_cg_rc)." >&2
    echo "  Fix: run the close ceremony (/aai-pr, or the close-work-item.mjs command printed above), or set close_gate: report-only in docs/ai/docs-audit.yaml on the pushed commit." >&2
    _cg_refused=1
  else
    echo "AAI:CLOSE-GATE: reported for $_cg_rref (close_gate=$_cg_mode; push allowed)"
  fi
done
exit "$_cg_refused"
PREPUSHHOOK
}

# write_prepush_hook — install the AAI:CLOSE-GATE pre-push body (skip,
# reporting so, when it is already AAI-managed and --force is not given).
# Same shape and same discipline as write_refguard_hook: callers
# ensure_hooks_dir first; write via a temp sibling and rename so a failed
# write can never truncate what was there; every branch guarded so the
# "Installed" line cannot print unless the write happened.
write_prepush_hook() {
  if [[ -f "$PREPUSH_PATH" && "$FORCE" != 1 ]] && has_marker_line "$PREPUSH_PATH" "$PREPUSH_MARKER"; then
    echo "AAI pre-push hook already installed at $PREPUSH_PATH. No action taken."
    return 0
  fi
  local tmp="$PREPUSH_PATH.aai-tmp.$$"
  if ! pre_push_body > "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: could not write $tmp (the effective hooks directory may be missing)." >&2
    return 1
  fi
  if ! chmod +x "$tmp" || ! mv -f "$tmp" "$PREPUSH_PATH"; then
    rm -f "$tmp"
    echo "ERROR: could not move $tmp into place at $PREPUSH_PATH." >&2
    return 1
  fi
  echo "Installed AAI pre-push hook (AAI:CLOSE-GATE) at $PREPUSH_PATH"
  echo "Effect: every push runs close-reconcile.mjs --check over the pushed range (report-only; close_gate: enforce refuses a default-branch push only)."
}

# guard_block_interior — the engine-owned bytes BETWEEN the two marker lines
# of a file (or of the shipped block when given no file): the only range an
# upgrade compares and replaces.
guard_block_interior() {
  awk -v b="$GUARD_BLOCK_BEGIN" -v e="$GUARD_BLOCK_END" '$0==b{p=1; next} $0==e{p=0} p' "$@"
}

# write_precommit_fresh — compose <shebang> + guard block + <index body minus
# its shebang> into the pre-commit slot via a temp sibling and rename.
write_precommit_fresh() {
  local tmp="$HOOK_PATH.aai-tmp.$$"
  # awk, not head/tail: the body is engine-owned (every line newline-
  # terminated), and awk reads its whole input, so no early-closing reader
  # ever SIGPIPEs the producer under this script's own pipefail.
  if ! { index_hook_body | awk 'NR==1'; guard_block_body; index_hook_body | awk 'NR>1'; } > "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: could not write $tmp (the effective hooks directory may be missing)." >&2
    return 1
  fi
  if ! chmod +x "$tmp" || ! mv -f "$tmp" "$HOOK_PATH"; then
    rm -f "$tmp"
    echo "ERROR: could not move $tmp into place at $HOOK_PATH." >&2
    return 1
  fi
  echo "Installed AAI pre-commit hook at $HOOK_PATH"
  echo "Effect: pre-commit-checks.sh now runs on every commit (secrets detection blocks; roughly four seconds per commit); on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
}

# upgrade_precommit_hook — the pre-commit slot already holds an AAI-marked
# file and --force was not given. The #414 / SPEC-0199 discipline: rewrite
# only what this installer can PROVE it owns, otherwise leave the file alone
# and say so — never rewrite, never add beside, never a "left untouched"
# message about something that was written.
#   - lstat first: a symlinked slot is refused, never followed out of the
#     repository;
#   - a CR-terminated first line is refused by name (an LF block inserted
#     under a CRLF shebang would produce a hook sh cannot start);
#   - a UTF-8 byte-order mark is refused by name (sh cannot start a hook
#     whose first bytes are not '#!'; inserting above the BOM would only
#     bury the shebang on line 20 — validation NB1);
#   - no guard block -> insert it after line 1 when that is a shebang, else
#     at line 1; every other byte stays as it was (the file may be a foreign
#     hook whose owner hand-merged the marker via --print); an END marker
#     with no BEGIN is refused rather than inserted above;
#   - exactly one block, BEGIN above END -> replace the interior between the
#     markers only when it differs from the shipped one; every byte outside
#     the interior is copied as-is (head/tail on line numbers, never a
#     line-normalising rewrite); a second run is byte-identical;
#   - more than one BEGIN or END marker -> refused: it cannot be proven
#     which block is the engine's;
#   - END above BEGIN -> refused BEFORE any write: with inverted markers no
#     interior can be located, and a refresh would drop every line after
#     the BEGIN (validation B1 — 150 user lines lost, the #414 class).
# Every write goes through a temp sibling and rename, and every message
# below describes exactly the bytes that path leaves on disk.
upgrade_precommit_hook() {
  if [[ -L "$HOOK_PATH" ]]; then
    echo "ERROR: $HOOK_PATH is a symlink. Refusing to rewrite through a symlink (the target may be outside this repository); replace the link with a regular file, or pass --force." >&2
    return 1
  fi
  if [[ "$(wc -l < "$HOOK_PATH" | tr -d ' ')" -eq 0 ]]; then
    echo "ERROR: $HOOK_PATH has no newline-terminated line; refusing to insert the AAI:GUARD-CHECKS block into it. Pass --force to rewrite the whole slot." >&2
    return 1
  fi
  if [[ "$(head -c 3 "$HOOK_PATH" | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]]; then
    echo "ERROR: $HOOK_PATH starts with a UTF-8 byte-order mark (EF BB BF); sh cannot start a hook whose first bytes are not '#!', so the AAI:GUARD-CHECKS block is not inserted into it. File left as it was. Strip the BOM, or pass --force to rewrite the whole slot." >&2
    return 1
  fi
  local first
  IFS= read -r first < "$HOOK_PATH" || true
  if [[ "$first" == *$'\r' ]]; then
    echo "ERROR: $HOOK_PATH has a CR-terminated first line (CRLF hook). Refusing to insert an LF block under it — sh could not start the result. Convert the hook to LF, or pass --force to rewrite the whole slot." >&2
    return 1
  fi
  local tmp="$HOOK_PATH.aai-tmp.$$"
  if ! grep -qF "$GUARD_BLOCK_BEGIN" "$HOOK_PATH"; then
    local stray_ends
    stray_ends="$(grep -cxF "$GUARD_BLOCK_END" "$HOOK_PATH" || true)"
    if [[ "$stray_ends" -ne 0 ]]; then
      echo "ERROR: $HOOK_PATH carries $stray_ends '$GUARD_BLOCK_END' line(s) and no '$GUARD_BLOCK_BEGIN'; refusing to insert a block above a stray END marker. File left as it was. Remove the END line by hand, or pass --force to rewrite the whole slot." >&2
      return 1
    fi
    if [[ "$first" == '#!'* ]]; then
      { head -n1 "$HOOK_PATH"; guard_block_body; tail -n +2 "$HOOK_PATH"; } > "$tmp" || { rm -f "$tmp"; echo "ERROR: could not write $tmp." >&2; return 1; }
    else
      { guard_block_body; cat "$HOOK_PATH"; } > "$tmp" || { rm -f "$tmp"; echo "ERROR: could not write $tmp." >&2; return 1; }
    fi
    if ! chmod +x "$tmp" || ! mv -f "$tmp" "$HOOK_PATH"; then
      rm -f "$tmp"
      echo "ERROR: could not move $tmp into place at $HOOK_PATH." >&2
      return 1
    fi
    echo "Upgraded AAI pre-commit hook at $HOOK_PATH: added the AAI:GUARD-CHECKS block (pre-commit-checks.sh now runs on every commit; secrets detection blocks)"
    return 0
  fi
  local begins ends
  begins="$(grep -cxF "$GUARD_BLOCK_BEGIN" "$HOOK_PATH" || true)"
  ends="$(grep -cxF "$GUARD_BLOCK_END" "$HOOK_PATH" || true)"
  if [[ "$begins" -ne 1 || "$ends" -ne 1 ]]; then
    echo "ERROR: $HOOK_PATH carries $begins '$GUARD_BLOCK_BEGIN' and $ends '$GUARD_BLOCK_END' line(s); refusing to guess which block is the installer's. File left as it was. Remove the extra markers by hand, or pass --force to rewrite the whole slot." >&2
    return 1
  fi
  # Line numbers of the one BEGIN and the one END (grep -n on a file: no
  # pipe, no early-closing reader). The order check runs BEFORE any write.
  local begin_ln end_ln
  begin_ln="$(grep -nxF "$GUARD_BLOCK_BEGIN" "$HOOK_PATH")"; begin_ln="${begin_ln%%:*}"
  end_ln="$(grep -nxF "$GUARD_BLOCK_END" "$HOOK_PATH")"; end_ln="${end_ln%%:*}"
  if [[ "$begin_ln" -gt "$end_ln" ]]; then
    echo "ERROR: $HOOK_PATH carries '$GUARD_BLOCK_END' (line $end_ln) BEFORE '$GUARD_BLOCK_BEGIN' (line $begin_ln): the markers are inverted, so no interior can be located and a refresh would drop every line after the BEGIN. File left as it was. Move the BEGIN line above the END line by hand, or pass --force to rewrite the whole slot." >&2
    return 1
  fi
  local shipped_tmp="$HOOK_PATH.aai-shipped.$$" current_tmp="$HOOK_PATH.aai-current.$$"
  guard_block_body | guard_block_interior > "$shipped_tmp"
  guard_block_interior "$HOOK_PATH" > "$current_tmp"
  if cmp -s "$current_tmp" "$shipped_tmp"; then
    rm -f "$shipped_tmp" "$current_tmp"
    echo "AAI pre-commit hook already installed at $HOOK_PATH. No action taken."
    return 0
  fi
  rm -f "$current_tmp"
  # Byte-exact outside the interior: lines 1..BEGIN are all newline-
  # terminated (END follows them), so head copies them verbatim; tail from
  # the END line copies the rest verbatim, a missing final newline included.
  { head -n "$begin_ln" "$HOOK_PATH"; cat "$shipped_tmp"; tail -n +"$end_ln" "$HOOK_PATH"; } > "$tmp" \
    || { rm -f "$tmp" "$shipped_tmp"; echo "ERROR: could not write $tmp." >&2; return 1; }
  rm -f "$shipped_tmp"
  if ! chmod +x "$tmp" || ! mv -f "$tmp" "$HOOK_PATH"; then
    rm -f "$tmp"
    echo "ERROR: could not move $tmp into place at $HOOK_PATH." >&2
    return 1
  fi
  echo "Refreshed the AAI:GUARD-CHECKS block at $HOOK_PATH (interior between the markers replaced; every other byte unchanged)"
}

# install_precommit_hook — the pre-commit slot's write path: fresh install
# when the slot is empty or --force was given, otherwise the marker-scoped
# upgrade above (a foreign file was already refused before any slot write).
install_precommit_hook() {
  if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]] && [[ "$FORCE" != 1 ]]; then
    upgrade_precommit_hook
    return $?
  fi
  write_precommit_fresh
}

# --decline-ref-guard / --arm-ref-guard are single-purpose actions on the
# ref-guard hook alone: dispatched here (after path resolution, before the
# --hooks-selected install/uninstall flow below) and exit before reaching it.
if [[ "$DECLINE_REF_GUARD" == 1 && "$ARM_REF_GUARD" == 1 ]]; then
  echo "ERROR: --decline-ref-guard and --arm-ref-guard are contradictory." >&2
  exit 2
fi
if [[ "$DECLINE_REF_GUARD" == 1 ]]; then
  decline_ref_guard || exit 1
  exit 0
fi
if [[ "$ARM_REF_GUARD" == 1 ]]; then
  arm_ref_guard || exit 1
  exit 0
fi

if [[ "$UNINSTALL" == 1 ]]; then
  if [[ "$WANT_INDEX" == 1 ]]; then  # AC-01 uninstall selection: index
    if [[ -f "$HOOK_PATH" ]] && has_marker_line "$HOOK_PATH" "$MARKER"; then
      rm "$HOOK_PATH"
      echo "Uninstalled AAI pre-commit hook from $HOOK_PATH"
    else
      echo "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
    fi
  fi
  if [[ "$WANT_REFGUARD" == 1 ]]; then  # AC-01 uninstall selection: ref-guard
    if [[ -f "$REFTX_PATH" ]] && has_marker_line "$REFTX_PATH" "$REFTX_MARKER"; then
      rm "$REFTX_PATH"
      echo "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $REFTX_PATH"
    else
      echo "No AAI reference-transaction hook found (or hook is not AAI-managed). No action taken."
    fi
  fi
  if [[ "$WANT_CLOSEGATE" == 1 ]]; then  # uninstall selection: close-gate
    if [[ -f "$PREPUSH_PATH" ]] && has_marker_line "$PREPUSH_PATH" "$PREPUSH_MARKER"; then
      rm "$PREPUSH_PATH"
      echo "Uninstalled AAI pre-push hook (AAI:CLOSE-GATE) from $PREPUSH_PATH"
    else
      echo "No AAI pre-push hook found (or hook is not AAI-managed). No action taken."
    fi
  fi
  exit 0
fi

# Selection-aware (Spec-AC-02): a foreign file in a slot this run was NOT
# asked to touch is not a reason to refuse — only a SELECTED slot's foreign
# file blocks the run, and it blocks the WHOLE run (both slots stay
# untouched), so the selected set is never partially installed.
FOREIGN=0
if [[ "$WANT_INDEX" == 1 && -f "$HOOK_PATH" && "$FORCE" != 1 ]] && ! has_marker_line "$HOOK_PATH" "$MARKER"; then  # AC-02 foreign check: index
  echo "ERROR: $HOOK_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the snippets manually:" >&2
  echo "       $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print               # the AAI:INDEX-AUTOGEN body" >&2
  echo "       $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print guard-checks  # the AAI:GUARD-CHECKS block (put it first)" >&2
  FOREIGN=1
fi
if [[ "$WANT_REFGUARD" == 1 && -f "$REFTX_PATH" && "$FORCE" != 1 ]] && ! has_marker_line "$REFTX_PATH" "$REFTX_MARKER"; then  # AC-02 foreign check: ref-guard
  foreign_reftx_refusal
  FOREIGN=1
fi
if [[ "$WANT_CLOSEGATE" == 1 && -f "$PREPUSH_PATH" && "$FORCE" != 1 ]] && ! has_marker_line "$PREPUSH_PATH" "$PREPUSH_MARKER"; then  # foreign check: close-gate
  foreign_prepush_refusal
  FOREIGN=1
fi
if [[ "$FOREIGN" == 1 ]]; then
  exit 1
fi

ensure_hooks_dir || exit 1

if [[ "$WANT_INDEX" == 1 ]]; then  # AC-01 write selection: index
  install_precommit_hook || exit 1
fi  # AC-01 write selection: index (close)

if [[ "$WANT_REFGUARD" == 1 ]]; then  # AC-01 write selection: ref-guard
  # N1 (validation round 1): a declared decline must survive a plain
  # re-install -- the exact shape /aai-update's SKILL_UPDATE step 4 runs on
  # every successful sync, with no flags. D1's "the explicit command wins"
  # names --arm-ref-guard, not an automatic documentation-refresh side
  # effect, so a bare `--hooks all`/no-flag run honours a declared decline
  # the same way it would honour one typed by hand. Two explicit overrides
  # stay available: --arm-ref-guard (a separate dispatch above this whole
  # --hooks flow, which never consults the policy at all -- always wins) and
  # --force, whose existing contract is already "proceed past a protective
  # refusal in this slot" (a foreign hook) and is the natural one-flag way to
  # push a plain --hooks run past a decline too, without switching commands.
  #
  # --force is intentionally scoped to the HOOK, not the DECLARATION
  # (validation round 2, NB3): after a --force past a decline, the guard is
  # installed but docs/ai/docs-audit.yaml still reads `ref_guard: declined`.
  # This is left as-is rather than made to also rewrite the key, because
  # --force's contract predates this scope ("proceed past a protective
  # refusal in this slot") and already means something narrower than "also
  # change the committed declaration" -- conflating the two would make a
  # one-off override on THIS run silently rewrite a file D2 defines as a
  # deliberate, reviewable act. Nothing is unsafe about the gap: D4 makes
  # every reader (CAT-17, the plain-install skip above) trust an actually-
  # installed hook over the stale declaration, so the file is inert once the
  # hook is present. A consumer who wants the DECLARATION changed too runs
  # --arm-ref-guard, which is what that command is for.
  if [[ "$FORCE" != 1 ]] && [[ "$(read_ref_guard_policy "$CONFIG_PATH")" == "declined" ]]; then
    echo "Skipped AAI reference-transaction hook (AAI:REF-GUARD): $CONFIG_PATH declares ref_guard: declined."
    echo "Re-arm with: bash $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard (or pass --force)."
    WANT_REFGUARD=0
  else
    write_refguard_hook
  fi
fi  # AC-01 write selection: ref-guard (close)

if [[ "$WANT_CLOSEGATE" == 1 ]]; then  # write selection: close-gate
  # No decline dial of its own: the hook's verdict is already dialled by
  # `close_gate` in docs/ai/docs-audit.yaml (D8), read from the pushed commit.
  write_prepush_hook || exit 1
fi  # write selection: close-gate (close)

# Post-condition (PR #304 Codex P1): exit 0 must mean "git will run these",
# never "a write succeeded somewhere". /aai-update reads this exit code as
# proof of protection, so a hook that landed off the effective path — or that
# lost its executable bit — has to end this script non-zero. Selection-aware
# (Spec-AC-02): attestation covers exactly the SELECTED set, so exit 0 keeps
# meaning "git will run what I installed" — an unselected hook this run never
# touched is not attested.
ATTEST_OK=1
if [[ "$WANT_INDEX" == 1 ]]; then  # AC-02 attestation selection: index
  attest_effective pre-commit "$MARKER" || ATTEST_OK=0
fi
if [[ "$WANT_REFGUARD" == 1 ]]; then  # AC-02 attestation selection: ref-guard
  attest_effective reference-transaction "$REFTX_MARKER" || ATTEST_OK=0
fi
if [[ "$WANT_CLOSEGATE" == 1 ]]; then  # attestation selection: close-gate
  attest_effective pre-push "$PREPUSH_MARKER" || ATTEST_OK=0
fi
if [[ "$ATTEST_OK" != 1 ]]; then
  echo "ERROR: installation did NOT leave an active hook at the path git resolves." >&2
  echo "       Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'." >&2
  exit 1
fi

echo "Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall"
