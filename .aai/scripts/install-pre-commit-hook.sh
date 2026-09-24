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
#   ./.aai/scripts/install-pre-commit-hook.sh --print [index|ref-guard]
#                                                        # emit a hook body to
#                                                        # stdout for a manual
#                                                        # merge (bare --print
#                                                        # keeps the index body)
#   ./.aai/scripts/install-pre-commit-hook.sh --hooks <csv>
#                                                        # select which hook(s)
#                                                        # to install/uninstall
#                                                        # -- closed set:
#                                                        # index, ref-guard, all
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
# Idempotent per hook. Refuses to overwrite a non-AAI hook unless --force is
# given (checked for BOTH hooks before writing either, so a foreign hook in
# one slot never causes a partial install of the other). A declared
# `ref_guard: declined` (docs/ai/docs-audit.yaml) is honoured by a plain
# install: the ref-guard hook is skipped, not silently re-armed. Override
# with --arm-ref-guard or --force.

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
      # --print's hook argument is OPTIONAL: only a literal 'index' or
      # 'ref-guard' immediately after it is consumed, so `--print --force`
      # still parses --force as its own flag (bare --print stays valid).
      if [[ $((_i + 1)) -lt $_ARGC ]]; then
        case "${_ARGV[$((_i + 1))]}" in
          index|ref-guard)
            PRINT_HOOK="${_ARGV[$((_i + 1))]}"
            _i=$((_i + 1))
            ;;
        esac
      fi
      ;;
    --hooks)
      _i=$((_i + 1))
      if [[ $_i -ge $_ARGC ]]; then
        echo "ERROR: --hooks requires a value (closed set: index, ref-guard, all)" >&2
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

# --hooks <csv> over the closed set index/ref-guard/all (D6), default all —
# resolved once into the two booleans every selection-aware guard below
# consults. An unknown token exits 2 naming the closed set and writes
# nothing (checked before any repo/hook state is touched).
#
# --hooks "" (validation round 1, N2): an empty string is not a member of the
# closed set either, but the csv loop below only iterates while the remainder
# is non-empty, so an empty HOOKS_ARG used to fall straight through with both
# booleans still 0 -- exit 0, nothing installed, the success footer printed
# anyway. The .ps1 twin already rejected it (its foreach over -split ','
# yields one empty token, which hits its own closed-set default branch).
# Rejected here explicitly so the twins agree.
if [[ -z "$HOOKS_ARG" ]]; then
  echo "ERROR: unknown --hooks value: '' (closed set: index, ref-guard, all)" >&2
  exit 2
fi
WANT_INDEX=0
WANT_REFGUARD=0
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
    all) WANT_INDEX=1; WANT_REFGUARD=1 ;;
    *)
      echo "ERROR: unknown --hooks value: '$_hooks_tok' (closed set: index, ref-guard, all)" >&2
      exit 2
      ;;
  esac
done

# --print [index|ref-guard]: emit a hook body to stdout so a foreign-hook
# owner can hand-merge it, without touching any repo state. Bare --print (or
# --print index) keeps emitting the AAI:INDEX-AUTOGEN body (TEST-314 muscle
# memory, D5); --print ref-guard emits the AAI:REF-GUARD body. Both are
# extracted from this script's own heredocs (never a second copy) so neither
# can drift from what --hooks would actually install (PR #302 Copilot; D5).
if [[ "$PRINT" == 1 ]]; then
  case "$PRINT_HOOK" in
    ref-guard)
      awk '/^cat > "\$REFTX_PATH" <<.REFTXHOOK.$/{p=1; next} /^REFTXHOOK$/{if(p){exit}} p' "$0"
      ;;
    *)
      awk '/^cat > "\$HOOK_PATH" <<.HOOK.$/{p=1; next} /^HOOK$/{if(p){exit}} p' "$0"
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
HOOKS_DIR="$(dirname "$REFTX_PATH")"
MARKER="# AAI:INDEX-AUTOGEN"
REFTX_MARKER="# AAI:REF-GUARD"
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

# write_refguard_hook — install the AAI:REF-GUARD reference-transaction hook
# body (skip, reporting so, when it is already AAI-managed and --force is not
# given). Shared by the normal --hooks ref-guard write path below AND
# arm_ref_guard (Spec-AC-05), so the heredoc's bytes live in exactly ONE
# place — D9: no byte of the installed hook body may drift between callers.
write_refguard_hook() {
  if [[ -f "$REFTX_PATH" && "$FORCE" != 1 ]] && grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then
    echo "AAI reference-transaction hook already installed at $REFTX_PATH. No action taken."
    return 0
  fi
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
  [[ -f "$REFTX_PATH" ]] && grep -qF "$REFTX_MARKER" "$REFTX_PATH" && reftx_is_aai=1  # AC-05 decline removal: foreign-marker test
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
  if [[ -f "$REFTX_PATH" && "$FORCE" != 1 ]] && ! grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then
    foreign_reftx_refusal
    return 1
  fi
  write_refguard_hook
  attest_effective reference-transaction "$REFTX_MARKER" || return 1
  write_ref_guard_policy armed || return 1
  echo "Recorded ref_guard: armed in $CONFIG_PATH"
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
    if [[ -f "$HOOK_PATH" ]] && grep -qF "$MARKER" "$HOOK_PATH"; then
      rm "$HOOK_PATH"
      echo "Uninstalled AAI pre-commit hook from $HOOK_PATH"
    else
      echo "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
    fi
  fi
  if [[ "$WANT_REFGUARD" == 1 ]]; then  # AC-01 uninstall selection: ref-guard
    if [[ -f "$REFTX_PATH" ]] && grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then
      rm "$REFTX_PATH"
      echo "Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from $REFTX_PATH"
    else
      echo "No AAI reference-transaction hook found (or hook is not AAI-managed). No action taken."
    fi
  fi
  exit 0
fi

# Selection-aware (Spec-AC-02): a foreign file in a slot this run was NOT
# asked to touch is not a reason to refuse — only a SELECTED slot's foreign
# file blocks the run, and it blocks the WHOLE run (both slots stay
# untouched), so the selected set is never partially installed.
FOREIGN=0
if [[ "$WANT_INDEX" == 1 && -f "$HOOK_PATH" && "$FORCE" != 1 ]] && ! grep -qF "$MARKER" "$HOOK_PATH"; then  # AC-02 foreign check: index
  echo "ERROR: $HOOK_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the snippet manually:" >&2
  echo "       $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print" >&2
  FOREIGN=1
fi
if [[ "$WANT_REFGUARD" == 1 && -f "$REFTX_PATH" && "$FORCE" != 1 ]] && ! grep -qF "$REFTX_MARKER" "$REFTX_PATH"; then  # AC-02 foreign check: ref-guard
  foreign_reftx_refusal
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

if [[ "$WANT_INDEX" == 1 ]]; then  # AC-01 write selection: index
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
chmod +x "$HOOK_PATH"
echo "Installed AAI pre-commit hook at $HOOK_PATH"
echo "Effect: on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
fi
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
if [[ "$ATTEST_OK" != 1 ]]; then
  echo "ERROR: installation did NOT leave an active hook at the path git resolves." >&2
  echo "       Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'." >&2
  exit 1
fi

echo "Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall"
