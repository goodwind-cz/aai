#!/usr/bin/env bash
#
# Test: git reference-transaction ref-guard
# (docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md)
#
# Verifies the AAI:REF-GUARD reference-transaction hook written by
# .aai/scripts/install-pre-commit-hook.{sh,ps1}: a marker-less refs/heads/main
# ref update is refused (Spec-AC-01), AAI_GIT_WRITE=1 allows it exactly as an
# unguarded repository would (Spec-AC-02), reads and non-main ref writes are
# unaffected (Spec-AC-03, including the allocate-doc-number.mjs seam), a
# disposable clone of a guarded checkout carries no guard (Spec-AC-04), the
# installer contract (Spec-AC-05), the aai-doctor category (Spec-AC-06), the
# live dogfood arm on this repository (Spec-AC-07), this suite's own
# byte-unchanged .git/hooks pin (Spec-AC-08), and the canon-surface pin
# (Spec-AC-09).
#
# HAZ-SCRATCH: every installer invocation below targets a path under this
# suite's own mktemp -d ($TMP_ROOT), EXCEPT the deliberate, spec-sanctioned
# TEST-313 live probe against $PROJECT_ROOT, which never installs or removes
# anything — it only attempts a no-op (old-value == new-value) ref-transaction
# against refs/heads/main so a refusal (or an absent-guard skip) is provably
# side-effect-free either way. TEST-311 independently pins that
# $PROJECT_ROOT/.git/hooks is byte-unchanged across the whole suite run.
#
# Covers TEST-301..313 from
# docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-git-ref-guard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh"
INSTALLER_PS1="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1"
DOCTOR="$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs"

TMP_ROOT=""
FAILED=0
HOOKS_DIGEST_BEFORE=""

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }
# A NAMED, per-test skip (TEST-313 only): reported, never silent, never
# treated as a failure and never exits the whole suite.
log_named_skip() { echo "SKIP: $*"; }

check_deps() {
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$INSTALLER" ]] || log_skip "installer not found: $INSTALLER"
  [[ -f "$DOCTOR" ]] || log_skip "aai-doctor.mjs not found: $DOCTOR"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-git-ref-guard.XXXXXX")"
}

sha_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    echo "sha256sum"
  fi
}

# manifest_of <dir> — sorted "<hash>  <relpath>" lines for every file, or the
# literal string "ABSENT" when the directory does not exist (a hookless
# checkout is a valid state, never a fixture bug).
manifest_of() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "ABSENT"
    return 0
  fi
  (cd "$dir" && find . -type f | LC_ALL=C sort | xargs $(sha_cmd) 2>/dev/null)
}

# --- fixture builders --------------------------------------------------------

# new_repo <name> — an isolated git repo on branch "main" with one seed
# commit, deterministic identity+date (so two independently-built fixtures
# hash-match commit-for-commit; needed by TEST-304's log comparison). Echoes
# the absolute path under $TMP_ROOT (HAZ-SCRATCH).
new_repo() {
  local name="$1"
  local d="$TMP_ROOT/$name"
  rm -rf "$d"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "AAI Test"
  echo "seed" > "$d/seed.txt"
  git -C "$d" add seed.txt
  (cd "$d" && env \
      GIT_AUTHOR_NAME="AAI Test" GIT_AUTHOR_EMAIL="test@example.invalid" \
      GIT_COMMITTER_NAME="AAI Test" GIT_COMMITTER_EMAIL="test@example.invalid" \
      GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
      git commit -q -m "seed")
  printf '%s' "$d"
}

# install_guard <dir> [installer args...] — runs the REAL installer against
# ONLY <dir> (HAZ-SCRATCH / Spec-AC-08: never $PROJECT_ROOT).
install_guard() {
  local d="$1"; shift
  (cd "$d" && bash "$INSTALLER" "$@")
}

# commit_det <dir> <msg> [extra env "NAME=value" pairs...] — a deterministic,
# reproducible-hash commit (fixed identity+date; see new_repo). Extra args are
# passed through to `env` before `git commit`, e.g. AAI_GIT_WRITE=1.
commit_det() {
  local d="$1" msg="$2"; shift 2
  (cd "$d" && env "$@" \
      GIT_AUTHOR_NAME="AAI Test" GIT_AUTHOR_EMAIL="test@example.invalid" \
      GIT_COMMITTER_NAME="AAI Test" GIT_COMMITTER_EMAIL="test@example.invalid" \
      GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
      git commit -q --allow-empty -m "$msg")
}

# require_guard_installed <label> <dir> — hard precondition: <dir> must carry
# an AAI:REF-GUARD-marked reference-transaction hook. Several ACs (reads stay
# unaffected; a clone never inherits ANY hook) hold TRUE whether or not this
# mechanism exists at all, so without this precondition those tests would be
# tautologically green pre-change instead of a genuine RED (RED-first list,
# ## Test Plan). FAILs (loudly, naming the missing file) and returns 1 when
# the precondition is not met; returns 0 otherwise.
require_guard_installed() {
  local label="$1" dir="$2"
  if [[ ! -f "$dir/.git/hooks/reference-transaction" ]] || ! grep -qF "AAI:REF-GUARD" "$dir/.git/hooks/reference-transaction"; then
    log_fail "$label: setup precondition failed — reference-transaction hook (AAI:REF-GUARD) not installed in $dir"
    return 1
  fi
  return 0
}

# assert_clean_op <label> <dir> <cmd...> — runs cmd in dir; FAILs (via
# log_fail) and returns 1 if it exits non-zero or leaks the refusal text.
# Returns 0 on success. Callers aggregate the return values themselves (bash
# 3.2 has no nameref, so this cannot mutate a caller-named flag directly).
assert_clean_op() {
  local label="$1" dir="$2"; shift 2
  local out rc
  out="$(cd "$dir" && "$@" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    log_fail "TEST-305 $label: expected exit 0, got $rc: $out"
    return 1
  fi
  if grep -q "AAI:REF-GUARD" <<<"$out"; then
    log_fail "TEST-305 $label: unexpected refusal text leaked: $out"
    return 1
  fi
  return 0
}

# --- TEST-301 (Spec-AC-01) ---------------------------------------------------
# commit / branch-force-main / branch-delete-main / reset --hard each refused;
# refs/heads listing + HEAD commit count byte-identical before/after each
# attempt; stderr names AAI_GIT_WRITE. Per the 2026-08-28 amendment, "branch"
# and "branch -D" are exercised AGAINST refs/heads/main specifically (a
# same-branch force-move / a delete from another branch) — creating or
# deleting a NON-main branch is now the amended ALLOWED case, covered by
# TEST-305's reads-and-non-main-writes arm instead.
test_301_guarded_refusal() {
  local d; d="$(new_repo t301)"
  install_guard "$d" >/dev/null 2>&1
  # A marked second commit so 'reset --hard HEAD~1' has something to reset to
  # — the marker here is the deliberate, legitimate ride's-own-commit case.
  commit_det "$d" "second" AAI_GIT_WRITE=1 >/dev/null 2>&1

  local ok=1 rc out before_c before_r after_c after_r

  # -- commit --
  before_c="$(git -C "$d" rev-list --count HEAD)"
  before_r="$(git -C "$d" for-each-ref refs/heads)"
  out="$(cd "$d" && git commit -q --allow-empty -m x 2>&1)"; rc=$?
  after_c="$(git -C "$d" rev-list --count HEAD)"
  after_r="$(git -C "$d" for-each-ref refs/heads)"
  if [[ $rc -eq 0 ]]; then log_fail "TEST-301 commit: expected non-zero, got 0"; ok=0; fi
  if [[ "$before_c" != "$after_c" || "$before_r" != "$after_r" ]]; then
    log_fail "TEST-301 commit: ref state changed on refusal"; ok=0
  fi
  if ! grep -q "AAI_GIT_WRITE" <<<"$out"; then
    log_fail "TEST-301 commit: stderr does not name AAI_GIT_WRITE: $out"; ok=0
  fi

  # move off main so the next two operations exercise OUR hook rather than
  # git's own "cannot force-update the branch used by this worktree" guard.
  (cd "$d" && git checkout -q -b t301-other) >/dev/null 2>&1

  # -- branch -f main <sha> (force-move main while it is NOT checked out) --
  # PR #302 Copilot: using `rev-parse HEAD` here (== main's own current tip,
  # since t301-other was just branched off it) makes old==new — a no-op ref
  # update whose refusal proof would depend on whether THIS git version even
  # runs a reference-transaction for a no-op. HEAD~1 (the "seed" commit,
  # distinct from main's "second"-commit tip) forces a REAL ref movement so
  # the hook must actually fire and refuse it.
  before_r="$(git -C "$d" for-each-ref refs/heads)"
  local newsha; newsha="$(git -C "$d" rev-parse HEAD~1)"
  if [[ "$newsha" == "$(git -C "$d" rev-parse refs/heads/main)" ]]; then
    log_fail "TEST-301 branch -f main: fixture precondition broken — HEAD~1 equals main's current tip, so this would still be a no-op"
    ok=0
  fi
  out="$(cd "$d" && git branch -f main "$newsha" 2>&1)"; rc=$?
  after_r="$(git -C "$d" for-each-ref refs/heads)"
  if [[ $rc -eq 0 ]]; then log_fail "TEST-301 branch -f main: expected non-zero, got 0"; ok=0; fi
  if [[ "$before_r" != "$after_r" ]]; then
    log_fail "TEST-301 branch -f main: refs/heads changed on refusal"; ok=0
  fi

  # -- branch -D main (from another branch) --
  before_r="$(git -C "$d" for-each-ref refs/heads)"
  out="$(cd "$d" && git branch -D main 2>&1)"; rc=$?
  after_r="$(git -C "$d" for-each-ref refs/heads)"
  if [[ $rc -eq 0 ]]; then log_fail "TEST-301 branch -D main: expected non-zero, got 0"; ok=0; fi
  if [[ "$before_r" != "$after_r" ]]; then
    log_fail "TEST-301 branch -D main: refs/heads changed on refusal"; ok=0
  fi

  (cd "$d" && git checkout -q main) >/dev/null 2>&1

  # -- reset --hard --
  before_c="$(git -C "$d" rev-list --count HEAD)"
  before_r="$(git -C "$d" for-each-ref refs/heads)"
  out="$(cd "$d" && git reset --hard HEAD~1 2>&1)"; rc=$?
  after_c="$(git -C "$d" rev-list --count HEAD)"
  after_r="$(git -C "$d" for-each-ref refs/heads)"
  if [[ $rc -eq 0 ]]; then log_fail "TEST-301 reset --hard: expected non-zero, got 0"; ok=0; fi
  if [[ "$before_c" != "$after_c" || "$before_r" != "$after_r" ]]; then
    log_fail "TEST-301 reset --hard: ref state changed on refusal"; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-301 commit / branch -f main / branch -D main / reset --hard each refused, refs byte-identical before/after, stderr names AAI_GIT_WRITE"
}

# --- TEST-302 (Spec-AC-01) — THE MUTATION PROOF ------------------------------
# HAZ-RESTORE: the mutation lands on the fixture's OWN byte copy of the
# installed hook, never on .aai/scripts/install-pre-commit-hook.sh and never
# on a hook under $PROJECT_ROOT/.git.
test_302_mutation_proof() {
  local base; base="$(new_repo t302base)"
  install_guard "$base" >/dev/null 2>&1
  local mutant="$TMP_ROOT/t302-mutant"
  rm -rf "$mutant"
  cp -R "$base" "$mutant"

  cat > "$mutant/.git/hooks/reference-transaction" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$mutant/.git/hooks/reference-transaction"

  local before_c out rc after_c
  before_c="$(git -C "$mutant" rev-list --count HEAD)"
  out="$(cd "$mutant" && git commit -q --allow-empty -m mutated 2>&1)"; rc=$?
  after_c="$(git -C "$mutant" rev-list --count HEAD)"

  if [[ $rc -eq 0 && "$after_c" -eq $((before_c + 1)) ]]; then
    log_pass "TEST-302 mutation proof: a broken guard (unconditional exit 0) lets the marker-less commit through — proves TEST-301/303's refusal assertions actually discriminate a working guard from a broken one"
  else
    log_fail "TEST-302 mutation proof: expected the mutated guard to let the commit through (rc=0, count+1); got rc=$rc before=$before_c after=$after_c ($out)"
  fi
}

# --- TEST-303 (Spec-AC-01) — THE UNMUTATED CONTROL ---------------------------
test_303_unmutated_control() {
  local d; d="$(new_repo t303)"
  install_guard "$d" >/dev/null 2>&1

  local before_c before_r out rc after_c after_r
  before_c="$(git -C "$d" rev-list --count HEAD)"
  before_r="$(git -C "$d" for-each-ref refs/heads)"
  out="$(cd "$d" && git commit -q --allow-empty -m x 2>&1)"; rc=$?
  after_c="$(git -C "$d" rev-list --count HEAD)"
  after_r="$(git -C "$d" for-each-ref refs/heads)"

  if [[ $rc -ne 0 && "$before_c" == "$after_c" && "$before_r" == "$after_r" ]]; then
    log_pass "TEST-303 unmutated control: same fixture shape as TEST-302, hook unmutated, refuses with zero ref movement (rc=$rc)"
  else
    log_fail "TEST-303 unmutated control: expected refusal + zero ref movement; got rc=$rc before=$before_c/$before_r after=$after_c/$after_r ($out)"
  fi
}

# --- TEST-304 (Spec-AC-02) ----------------------------------------------------
# AAI_GIT_WRITE=1 makes the guarded fixture behave EXACTLY like an unguarded
# control: same four operations exit 0, and git log --format=%T%P%s matches
# byte-for-byte after the commit+reset round trip (deterministic identity+date
# from new_repo/commit_det makes the comparison meaningful, not coincidental).
test_304_marker_allows() {
  local g u
  g="$(new_repo t304g)"; install_guard "$g" >/dev/null 2>&1
  require_guard_installed "TEST-304" "$g" || return
  u="$(new_repo t304u)"

  local ok=1 rc

  commit_det "$g" "op-commit" AAI_GIT_WRITE=1; rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 commit (guarded+marker) expected 0, got $rc"; ok=0; }
  commit_det "$u" "op-commit"; rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 commit (unguarded control) expected 0, got $rc"; ok=0; }

  (cd "$g" && AAI_GIT_WRITE=1 git reset -q --hard HEAD~1); rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 reset --hard (guarded+marker) expected 0, got $rc"; ok=0; }
  (cd "$u" && git reset -q --hard HEAD~1); rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 reset --hard (unguarded control) expected 0, got $rc"; ok=0; }

  local glog ulog
  glog="$(git -C "$g" log --format='%T%P%s')"
  ulog="$(git -C "$u" log --format='%T%P%s')"
  if [[ "$glog" != "$ulog" ]]; then
    log_fail "TEST-304 git log --format=%T%P%s diverged from the unguarded control: guarded=[$glog] control=[$ulog]"
    ok=0
  fi

  (cd "$g" && git checkout -q -b t304-other); rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 checkout -b (guarded, non-main, no marker needed) expected 0, got $rc"; ok=0; }
  (cd "$u" && git checkout -q -b t304-other); rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 checkout -b (unguarded control) expected 0, got $rc"; ok=0; }

  local gsha usha
  gsha="$(git -C "$g" rev-parse HEAD)"
  (cd "$g" && AAI_GIT_WRITE=1 git branch -f main "$gsha"); rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 branch -f main (guarded+marker) expected 0, got $rc"; ok=0; }
  usha="$(git -C "$u" rev-parse HEAD)"
  (cd "$u" && git branch -f main "$usha"); rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 branch -f main (unguarded control) expected 0, got $rc"; ok=0; }

  (cd "$g" && AAI_GIT_WRITE=1 git branch -D main) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 branch -D main (guarded+marker) expected 0, got $rc"; ok=0; }
  (cd "$u" && git branch -D main) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-304 branch -D main (unguarded control) expected 0, got $rc"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-304 all four operations exit 0 with AAI_GIT_WRITE=1, and git log --format=%T%P%s matches an unguarded control fixture byte-for-byte"
}

# --- TEST-305 (Spec-AC-03) ----------------------------------------------------
test_305_reads_unaffected() {
  local d; d="$(new_repo t305)"
  install_guard "$d" >/dev/null 2>&1
  require_guard_installed "TEST-305" "$d" || return
  local bare="$TMP_ROOT/t305-origin.git"
  git init -q --bare "$bare"
  (cd "$d" && git push -q "$bare" main)
  (cd "$d" && git remote add origin "$bare")
  (cd "$d" && git checkout -q -b other) >/dev/null 2>&1
  local wt="$TMP_ROOT/t305-wt"
  rm -rf "$wt"

  local ok=1
  assert_clean_op "status"                "$d" git status || ok=0
  assert_clean_op "log"                   "$d" git log --oneline || ok=0
  assert_clean_op "rev-parse"             "$d" git rev-parse HEAD || ok=0
  assert_clean_op "diff"                  "$d" git diff || ok=0
  assert_clean_op "checkout existing branch" "$d" git checkout -q main || ok=0
  assert_clean_op "worktree add --detach" "$d" git worktree add --detach -q "$wt" HEAD || ok=0
  assert_clean_op "fetch"                 "$d" git fetch origin || ok=0
  assert_clean_op "tag"                   "$d" git tag t305tag || ok=0

  (cd "$d" && git worktree remove --force "$wt") >/dev/null 2>&1
  rm -rf "$wt"

  [[ $ok -eq 1 ]] && log_pass "TEST-305 status/log/rev-parse/diff/checkout/worktree-add/fetch/tag all exit 0 with no refusal text"
}

# --- TEST-306 (Spec-AC-03) — SEAM: allocate-doc-number.mjs ------------------
# The guard is armed AFTER repo setup so only the allocator's own writes
# (commit-tree + push to origin refs/aai/docnums/*, no local refs/heads write)
# are under test.
test_306_allocator_seam() {
  local d="$TMP_ROOT/t306"
  local bare="$TMP_ROOT/t306-origin.git"
  rm -rf "$d" "$bare"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/rfc"
  local f
  for f in allocate-doc-number.mjs generate-docs-index.mjs docs-audit.mjs \
           append-event.mjs spec-lint.mjs pre-commit-checks.sh; do
    cp "$PROJECT_ROOT/.aai/scripts/$f" "$d/.aai/scripts/$f" 2>/dev/null || true
  done
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/" 2>/dev/null || true

  git -C "$d" init -q -b main
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "AAI Test"
  printf 'docs/INDEX.audit.md\n' > "$d/.gitignore"
  (cd "$d" && git add -A && git commit -qm "chore: vendor scripts")
  git init -q --bare "$bare"
  (cd "$d" && git remote add origin "$bare")

  cat > "$d/docs/rfc/RFC-DRAFT-t306.md" <<'MD'
---
id: t306
type: rfc
number: null
status: draft
links:
  pr: []
---
# Draft t306
MD
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft t306")

  install_guard "$d" >/dev/null 2>&1

  local out rc
  out="$(cd "$d" && node .aai/scripts/allocate-doc-number.mjs --path docs/rfc/RFC-DRAFT-t306.md --base-ref main 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    log_fail "TEST-306 allocator seam: expected exit 0, got $rc: $out"
    return
  fi
  if ! git -C "$bare" for-each-ref refs/aai/docnums 2>/dev/null | grep -q "RFC-0001"; then
    log_fail "TEST-306 allocator seam: refs/aai/docnums/RFC-0001 not found in bare origin"
    return
  fi
  log_pass "TEST-306 allocator seam: allocate-doc-number.mjs exits 0 and reserves refs/aai/docnums under an armed guard"
}

# --- TEST-307 (Spec-AC-04) — SEAM: SPEC-0155 disposable clone ---------------
test_307_clone_seam() {
  local d; d="$(new_repo t307)"
  install_guard "$d" >/dev/null 2>&1
  require_guard_installed "TEST-307" "$d" || return
  local clone="$TMP_ROOT/t307-clone"
  rm -rf "$clone"

  local out rc
  out="$(git clone --local --no-hardlinks --quiet "$d" "$clone" 2>&1)"; rc=$?
  if [[ $rc -ne 0 || -n "$out" ]]; then
    log_fail "TEST-307 clone: expected exit 0 with empty stderr, got rc=$rc out=[$out]"
    return
  fi
  if [[ -f "$clone/.git/hooks/reference-transaction" ]]; then
    log_fail "TEST-307 clone: the clone inherited the reference-transaction hook"
    return
  fi
  local crc
  # A fresh clone inherits no local identity, and CI runners have no global
  # one either — without this the commit fails 128 for a reason that has
  # nothing to do with the guard. It passed locally only because this machine
  # has a global user.email; the arm was measuring the developer's config.
  git -C "$clone" config user.email "test@aai.local"
  git -C "$clone" config user.name "AAI Test"
  (cd "$clone" && git commit -q --allow-empty -m "clone commit no marker"); crc=$?
  if [[ $crc -ne 0 ]]; then
    log_fail "TEST-307 clone: marker-less commit inside the clone expected exit 0, got $crc"
    return
  fi
  log_pass "TEST-307 git clone --local --no-hardlinks from a guarded source exits 0 with empty stderr; the clone carries no guard and a marker-less commit inside it succeeds"
}

# --- TEST-308 (Spec-AC-05) — installer contract ------------------------------
# Regression pin: sha256 of the AAI:INDEX-AUTOGEN pre-commit hook body BEFORE
# this scope added the reference-transaction hook, measured against
# `git show HEAD:.aai/scripts/install-pre-commit-hook.sh` (the pre-change
# installer, still committed history at RED-authoring time) run through the
# same fixture technique used below. Pinned as a literal so the check stays
# meaningful after this scope's own commit rewrites HEAD.
PRECOMMIT_SHA256_BASELINE="9a3d1e5a50250572b07ccf35793f7fe22afcc929bd56d56984a423b8fcfdcea2"

test_308_installer_contract() {
  local ok=1

  # 1. first run installs both
  local d; d="$(new_repo t308)"
  install_guard "$d" >/dev/null 2>&1
  [[ -f "$d/.git/hooks/pre-commit" ]] || { log_fail "TEST-308: pre-commit not installed"; ok=0; }
  [[ -f "$d/.git/hooks/reference-transaction" ]] || { log_fail "TEST-308: reference-transaction not installed"; ok=0; }

  # 1b. installed pre-commit matches the pre-change installer's own product.
  local pc_hash
  pc_hash="$($(sha_cmd) "$d/.git/hooks/pre-commit" | awk '{print $1}')"
  if [[ "$pc_hash" != "$PRECOMMIT_SHA256_BASELINE" ]]; then
    log_fail "TEST-308: installed pre-commit hook body changed (got $pc_hash, want $PRECOMMIT_SHA256_BASELINE) — the ref-guard addition must not touch AAI:INDEX-AUTOGEN's bytes"
    ok=0
  fi

  # 2. byte-identical re-run
  cp "$d/.git/hooks/pre-commit" "$TMP_ROOT/t308-pc.snap"
  cp "$d/.git/hooks/reference-transaction" "$TMP_ROOT/t308-rt.snap"
  install_guard "$d" >/dev/null 2>&1
  cmp -s "$TMP_ROOT/t308-pc.snap" "$d/.git/hooks/pre-commit" || { log_fail "TEST-308: re-run changed pre-commit bytes"; ok=0; }
  cmp -s "$TMP_ROOT/t308-rt.snap" "$d/.git/hooks/reference-transaction" || { log_fail "TEST-308: re-run changed reference-transaction bytes"; ok=0; }

  # 3. a foreign reference-transaction hook refuses ATOMICALLY (neither hook
  #    is written), and leaves the foreign file untouched.
  local d2; d2="$(new_repo t308f)"
  mkdir -p "$d2/.git/hooks"
  printf '#!/bin/sh\necho foreign\n' > "$d2/.git/hooks/reference-transaction"
  cp "$d2/.git/hooks/reference-transaction" "$TMP_ROOT/t308-foreign.snap"
  local rc
  install_guard "$d2" >/dev/null 2>&1; rc=$?
  [[ $rc -ne 0 ]] || { log_fail "TEST-308: foreign hook install expected non-zero, got 0"; ok=0; }
  cmp -s "$TMP_ROOT/t308-foreign.snap" "$d2/.git/hooks/reference-transaction" || { log_fail "TEST-308: foreign reference-transaction file was modified"; ok=0; }
  [[ -f "$d2/.git/hooks/pre-commit" ]] && { log_fail "TEST-308: pre-commit was installed despite the foreign reference-transaction refusal (must be atomic)"; ok=0; }

  # 4. --force overwrites
  install_guard "$d2" --force >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] || { log_fail "TEST-308: --force expected 0, got $rc"; ok=0; }
  grep -qF "AAI:REF-GUARD" "$d2/.git/hooks/reference-transaction" || { log_fail "TEST-308: --force did not install the AAI reference-transaction hook"; ok=0; }

  # 5. --uninstall removes only the AAI-managed hook, leaves a foreign one.
  local d3; d3="$(new_repo t308u)"
  install_guard "$d3" >/dev/null 2>&1
  printf '#!/bin/sh\necho foreign-pc\n' > "$d3/.git/hooks/pre-commit"
  install_guard "$d3" --uninstall >/dev/null 2>&1
  [[ -f "$d3/.git/hooks/pre-commit" ]] || { log_fail "TEST-308: uninstall removed a foreign pre-commit hook (must leave non-AAI hooks alone)"; ok=0; }
  [[ -f "$d3/.git/hooks/reference-transaction" ]] && { log_fail "TEST-308: uninstall left the AAI-managed reference-transaction hook in place"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-308 installer contract: install / byte-identical re-run / atomic foreign-hook refusal / --force / --uninstall, pre-commit byte-pinned to the pre-change installer's product"
}

# --- TEST-314 (PR #302 Copilot P2) — --print does what the error path says --
# The foreign-hook refusal (both slots) tells the operator to run
# `install-pre-commit-hook.sh --print` to get a mergeable snippet. Before
# this fix that flag did not exist — the arg parser's catch-all rejected it
# (exit 2, "unexpected argument"), so the operator's only guidance was a
# dead end. --print now emits the pre-commit hook body (extracted from the
# installer's own heredoc, so it can never drift from what --force installs)
# and exits 0 WITHOUT touching any repo/hook state.
test_314_print_flag() {
  local ok=1

  # --print succeeds and emits the real snippet — repo-independent (a
  # foreign-hook operator calling this from inside their OWN repo is exactly
  # the case this exists for, but the flag itself needs no repo at all).
  local out rc
  out="$(bash "$INSTALLER" --print 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    log_fail "TEST-314: --print expected exit 0, got $rc"; ok=0
  fi
  if ! grep -qF "AAI:INDEX-AUTOGEN" <<<"$out"; then
    log_fail "TEST-314: --print output does not contain the AAI:INDEX-AUTOGEN hook body: $out"; ok=0
  fi
  if ! grep -qF '#!/usr/bin/env bash' <<<"$out"; then
    log_fail "TEST-314: --print output does not look like the hook's own shebang-first body"; ok=0
  fi

  # --print never writes anything: no repo touched, no hook installed
  # anywhere reachable from cwd.
  local d; d="$(new_repo t314)"
  (cd "$d" && bash "$INSTALLER" --print >/dev/null 2>&1)
  [[ -f "$d/.git/hooks/pre-commit" ]] && { log_fail "TEST-314: --print installed a pre-commit hook (must be read-only)"; ok=0; }
  [[ -f "$d/.git/hooks/reference-transaction" ]] && { log_fail "TEST-314: --print installed a reference-transaction hook (must be read-only)"; ok=0; }

  # Mutation proof: --print is a NAMED flag, not "accept anything now" — a
  # genuinely unknown flag must still be rejected exit 2, same as before.
  local rc2
  bash "$INSTALLER" --this-flag-does-not-exist >/dev/null 2>&1; rc2=$?
  if [[ $rc2 -ne 2 ]]; then
    log_fail "TEST-314: an actually-unknown flag stopped being rejected (got $rc2, want 2) — --print was wired as a catch-all, not a specific case"; ok=0
  fi

  # The foreign-hook guidance itself must name a flag that now exists.
  grep -qE -- '--print' "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" \
    || { log_fail "TEST-314: the installer no longer mentions --print anywhere"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-314 --print emits the real pre-commit hook body read-only (exit 0, no writes), an unknown flag still exits 2" \
    || log_fail "TEST-314 --print flag"
}

# --- TEST-315 (PR #304 Codex P1) — installed where GIT resolves, not where ---
# --- the installer guessed ---------------------------------------------------
# Every assertion here is BEHAVIOURAL on purpose. The defect this arm exists
# for was invisible to file-presence checks: with core.hooksPath set, the
# installer wrote .git/hooks/reference-transaction, exited 0, and TEST-308's
# `[[ -f ... ]]` was perfectly happy — while git executed a different path and
# a marker-less commit moved refs/heads/main. So the question asked below is
# never "is a file there" but "does main actually refuse to move", which is
# the only thing the operator was promised.
test_315_effective_hooks_path() {
  local ok=1

  # assert_refuses <label> <dir> — a marker-less commit must be refused, main
  # must not move, and stderr must name the escape hatch; then the SAME commit
  # with AAI_GIT_WRITE=1 must succeed, so a wholly broken repo cannot pass this
  # by refusing everything.
  assert_refuses() {
    local label="$1" d="$2"
    local before after rc out sub=1
    before="$(git -C "$d" rev-parse refs/heads/main)"
    out="$(cd "$d" && git commit -q --allow-empty -m "t315 unmarked" 2>&1)"; rc=$?
    after="$(git -C "$d" rev-parse refs/heads/main)"
    if [[ $rc -eq 0 ]]; then
      log_fail "TEST-315 $label: marker-less commit to main expected non-zero, got 0 — the installed guard is INERT"; sub=0
    fi
    if [[ "$before" != "$after" ]]; then
      log_fail "TEST-315 $label: refs/heads/main MOVED ($before -> $after) despite an installer exit 0"; sub=0
    fi
    if [[ "$out" != *AAI_GIT_WRITE* ]]; then
      log_fail "TEST-315 $label: refusal text does not name AAI_GIT_WRITE: $out"; sub=0
    fi
    before="$(git -C "$d" rev-parse refs/heads/main)"
    commit_det "$d" "t315 marked" AAI_GIT_WRITE=1 >/dev/null 2>&1
    after="$(git -C "$d" rev-parse refs/heads/main)"
    if [[ "$before" == "$after" ]]; then
      log_fail "TEST-315 $label: AAI_GIT_WRITE=1 commit did NOT move main — this fixture refuses everything, so its refusal above proves nothing"; sub=0
    fi
    return $((1 - sub))
  }

  # A. core.hooksPath RELATIVE — the exact reproduction from the PR #304 report.
  local d; d="$(new_repo t315rel)"
  git -C "$d" config core.hooksPath .custom-hooks
  local irc; install_guard "$d" >/dev/null 2>&1; irc=$?
  [[ $irc -eq 0 ]] || { log_fail "TEST-315 relative-hooksPath: installer expected exit 0, got $irc"; ok=0; }
  assert_refuses "relative-hooksPath" "$d" || ok=0

  # B. core.hooksPath ABSOLUTE — a different code path in both twins (the
  #    resolver must NOT prepend the cwd to an already-rooted answer).
  local d2; d2="$(new_repo t315abs)"
  git -C "$d2" config core.hooksPath "$d2/abs-hooks"
  install_guard "$d2" >/dev/null 2>&1; irc=$?
  [[ $irc -eq 0 ]] || { log_fail "TEST-315 absolute-hooksPath: installer expected exit 0, got $irc"; ok=0; }
  assert_refuses "absolute-hooksPath" "$d2" || ok=0

  # C. LINKED WORKTREE, no hooksPath — the PR #302 fix must survive this
  #    change: git resolves to the SHARED common dir there, and installing
  #    from inside the worktree must still arm the guard for the whole repo.
  local d3; d3="$(new_repo t315wt)"
  local wt="$TMP_ROOT/t315wt-linked"
  if git -C "$d3" worktree add -q "$wt" -b t315branch >/dev/null 2>&1; then
    (cd "$wt" && bash "$INSTALLER") >/dev/null 2>&1; irc=$?
    [[ $irc -eq 0 ]] || { log_fail "TEST-315 linked-worktree: installer expected exit 0, got $irc"; ok=0; }
    assert_refuses "linked-worktree (installed from the worktree, main lives in the parent)" "$d3" || ok=0
    (cd "$d3" && git worktree remove --force "$wt") >/dev/null 2>&1
  else
    log_fail "TEST-315 linked-worktree: could not create the fixture worktree"
    ok=0
  fi

  # D. The refusal case. When the effective hooks path cannot be installed into,
  #    the installer must SAY SO and exit non-zero — a false success on a guard
  #    is worse than no guard, which is the whole point of this fix.
  local d4; d4="$(new_repo t315bad)"
  printf 'not a directory\n' > "$d4/hooks-as-a-file"
  git -C "$d4" config core.hooksPath "$d4/hooks-as-a-file"
  local out4 rc4
  out4="$(cd "$d4" && bash "$INSTALLER" 2>&1)"; rc4=$?
  if [[ $rc4 -eq 0 ]]; then
    log_fail "TEST-315 unusable-hooksPath: installer exited 0 on a hooks path it cannot install into (a false success on a guard)"; ok=0
  fi
  if [[ "$out4" != *"$d4/hooks-as-a-file"* ]]; then
    log_fail "TEST-315 unusable-hooksPath: the refusal does not name the effective hooks path it could not use: $out4"; ok=0
  fi

  # E. The other way a zero exit lies: the hook is at the right path but git
  #    silently skips it because it is not executable. The idempotent "already
  #    installed" branch does not rewrite or re-chmod it, so without a
  #    post-condition the installer reports success on a guard that is inert.
  #    Proven inert FIRST (the commit goes through), so the required non-zero
  #    exit below is measured against a real hole, not asserted about a string.
  local d5; d5="$(new_repo t315nx)"
  install_guard "$d5" >/dev/null 2>&1
  chmod -x "$d5/.git/hooks/reference-transaction"
  local before5 after5
  before5="$(git -C "$d5" rev-parse refs/heads/main)"
  (cd "$d5" && git commit -q --allow-empty -m "t315 nonexec") >/dev/null 2>&1
  after5="$(git -C "$d5" rev-parse refs/heads/main)"
  if [[ "$before5" == "$after5" ]]; then
    log_fail "TEST-315 non-executable: fixture precondition failed — git still refused, so this arm is not measuring a real hole"; ok=0
  else
    local out5 rc5
    out5="$(cd "$d5" && bash "$INSTALLER" 2>&1)"; rc5=$?
    if [[ $rc5 -eq 0 ]]; then
      log_fail "TEST-315 non-executable: installer exited 0 while the hook git resolves is not executable (git skips it) — a false success on a guard"; ok=0
    fi
    if [[ "$out5" != *"not executable"* ]]; then
      log_fail "TEST-315 non-executable: the installer does not tell the operator the resolved hook is not executable: $out5"; ok=0
    fi
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-315 with core.hooksPath relative/absolute and from a linked worktree, the installer exits 0 AND a marker-less commit to refs/heads/main is refused with main unmoved (AAI_GIT_WRITE=1 still passes); an unusable hooks path, and an already-present but non-executable hook, each exit non-zero naming the problem" \
    || log_fail "TEST-315 effective hooks path"
}

# --- TEST-309 (Spec-AC-05) — .ps1 twin, static -------------------------------
# F-R3 (code review 20260828T144437Z): the prior version of this arm ran its
# four greps over the WHOLE .ps1 file. Every one of those four patterns also
# occurs outside the hook body (SYNOPSIS at :6, Write-Host at :266, the
# $reftxMarker/$reftxPath assignments), so the arm could not tell a .ps1 that
# writes a working guard from one whose $reftxBody here-string was deleted
# entirely — mutation-proved by the reviewer. Fixed by extracting exactly the
# $reftxBody @'...'@ here-string (the text that is literally Set-Content'd
# into .git/hooks/reference-transaction) and asserting on THAT, not the file.
test_309_ps1_twin_static() {
  if [[ ! -f "$INSTALLER_PS1" ]]; then
    log_fail "TEST-309: $INSTALLER_PS1 not found"
    return
  fi
  local ok=1
  local reftx_body
  reftx_body="$(awk '
    /^\$reftxBody = @'"'"'$/ { capture=1; next }
    capture && /^'"'"'@$/    { capture=0; next }
    capture                  { print }
  ' "$INSTALLER_PS1")"
  if [[ -z "$reftx_body" ]]; then
    log_fail "TEST-309: could not extract the \$reftxBody @'...'@ here-string from .ps1 (delimiters moved, or the body is empty/missing)"
    ok=0
  fi
  # The marker is a comment by design, so it is asserted against the whole body.
  grep -qF "AAI:REF-GUARD" <<<"$reftx_body" || { log_fail "TEST-309: .ps1 reftxBody here-string missing the AAI:REF-GUARD marker"; ok=0; }

  # Everything below must be pinned to the CODE, not to prose that merely
  # mentions it. This body carries its own explanatory comment and a refusal
  # message, and both spell out "refs/heads/main" and "AAI_GIT_WRITE" in full;
  # a bare substring grep therefore passes even when the twin ships a guard
  # that watches the wrong ref or tests the variable backwards. Both of those
  # mutations were demonstrated to survive the substring form. Windows has no
  # live arm anywhere in this suite, so this static check is the ONLY thing
  # standing between an inverted .ps1 guard and a shipped release.
  local reftx_code
  reftx_code="$(printf '%s\n' "$reftx_body" \
    | awk '/<<'"'"'AAI_REF_GUARD_MSG'"'"'/ { inmsg=1 } inmsg { if ($0 ~ /^AAI_REF_GUARD_MSG$/) inmsg=0; next } { print }' \
    | grep -v '^[[:space:]]*#')"
  [[ -n "$reftx_code" ]] || { log_fail "TEST-309: stripping comments and the refusal message left no code (extraction shape moved)"; ok=0; }

  # The guarded ref is compared, not merely named.
  grep -qF 'if [ "$aai_ref" = "refs/heads/main" ]; then' <<<"$reftx_code" \
    || { log_fail "TEST-309: .ps1 twin does not COMPARE the updated ref against refs/heads/main (a mention in a comment is not a predicate)"; ok=0; }
  # ...and the escape hatch opens on equality with 1, not on anything else.
  grep -qF 'if [ "$AAI_GIT_WRITE" = "1" ]; then' <<<"$reftx_code" \
    || { log_fail "TEST-309: .ps1 twin does not gate on AAI_GIT_WRITE = 1 (an inverted or absent comparison would ship a guard that is backwards)"; ok=0; }

  # Assertion 4 targets the ASSIGNMENT that decides where the hook is written.
  # "hooks/reference-transaction" also appears in the .ps1 SYNOPSIS comment, so
  # anchoring on the bare string lets a retargeted $reftxPath pass unnoticed.
  # PR #302 Codex P2 moved the target off $repoRoot (a linked worktree's .git is
  # a FILE there) to $gitCommonDir; PR #304 Codex P1 moved it again, because
  # $gitCommonDir does not know about core.hooksPath and the installer was
  # exiting 0 on a hook git would never run. The write target is now whatever
  # git itself resolves, so this pins BOTH halves: the assignment reads from the
  # resolver, and the resolver asks git — pinning only the first would let a
  # resolver that quietly went back to --git-common-dir through.
  grep -qE "^\\\$reftxPath[[:space:]]*=[[:space:]]*Resolve-HookPath 'reference-transaction'" "$INSTALLER_PS1" \
    || { log_fail "TEST-309: .ps1 does not ASSIGN \$reftxPath from Resolve-HookPath 'reference-transaction' (the SYNOPSIS mentioning the hook is not the write target)"; ok=0; }
  grep -qF 'git rev-parse --git-path "hooks/$Name"' "$INSTALLER_PS1" \
    || { log_fail "TEST-309: .ps1's Resolve-HookPath does not ask git for the EFFECTIVE hooks path (git rev-parse --git-path) — a path derived any other way misses core.hooksPath"; ok=0; }
  grep -qF 'Join-Path $gitCommonDir "hooks/reference-transaction"' "$INSTALLER_PS1" \
    && { log_fail "TEST-309: .ps1 still writes the guard to \$gitCommonDir/hooks — that path ignores core.hooksPath (PR #304 Codex P1)"; ok=0; }

  # Assertion 5 (PR #302 Copilot P2): on Windows the .ps1 IS the entrypoint,
  # so the hook's OWN refusal message — printed by the hook itself, not by
  # this installer script — must give PowerShell-appropriate uninstall
  # guidance, not the bash command from the .sh twin.
  grep -qF 'Uninstall this guard: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall' <<<"$reftx_body" \
    || { log_fail "TEST-309: .ps1 twin's refusal message does not give a pwsh uninstall command"; ok=0; }
  grep -qF 'bash .aai/scripts/install-pre-commit-hook.sh --uninstall' <<<"$reftx_body" \
    && { log_fail "TEST-309: .ps1 twin's refusal message still tells a Windows operator to run bash — wrong entrypoint for this platform"; ok=0; }

  # Assertion 6 (PR #304 Copilot): the ESCAPE is the one command the operator
  # needs most at the moment this message appears, and PowerShell has no
  # `VAR=value command` prefix — so the POSIX form alone leaves a Windows
  # operator guessing. Verified by execution on pwsh 7.6.3: the child-process
  # form commits where the bare command is refused, and does not leak.
  grep -qF "pwsh -NoProfile -Command '\$env:AAI_GIT_WRITE=1; git commit ...'" <<<"$reftx_body" \
    || { log_fail "TEST-309: .ps1 twin's refusal message gives no PowerShell-valid form of the AAI_GIT_WRITE escape (the POSIX VAR=value prefix does not exist in PowerShell)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-309 .ps1 twin's \$reftxBody here-string carries the AAI:REF-GUARD marker, the refs/heads/main predicate, the AAI_GIT_WRITE check, the script writes to the EFFECTIVE hooks path git resolves (never \$gitCommonDir/hooks), and its refusal message gives pwsh (not bash) uninstall guidance AND a PowerShell-valid form of the AAI_GIT_WRITE escape"
}

# --- TEST-310 (Spec-AC-06) — aai-doctor category -----------------------------
test_310_doctor_category() {
  local d; d="$(new_repo t310)"
  mkdir -p "$d/.aai/scripts"
  cp "$INSTALLER" "$d/.aai/scripts/install-pre-commit-hook.sh"
  local ok=1

  local out
  out="$(node "$DOCTOR" --root "$d" 2>&1)"
  if ! echo "$out" | grep "^CAT-17" | grep -q "install-pre-commit-hook"; then
    log_fail "TEST-310: not-armed CAT-17 line missing the literal install-pre-commit-hook: $(echo "$out" | grep '^CAT-17')"
    ok=0
  fi
  if echo "$out" | grep "^CAT-17" | grep -qi "PASS"; then
    log_fail "TEST-310: hookless fixture unexpectedly reports CAT-17 as armed/PASS"
    ok=0
  fi

  install_guard "$d" >/dev/null 2>&1
  local out2
  out2="$(node "$DOCTOR" --root "$d" 2>&1)"
  if ! echo "$out2" | grep "^CAT-17" | grep -qi "PASS"; then
    log_fail "TEST-310: guarded fixture does not report CAT-17 armed/PASS: $(echo "$out2" | grep '^CAT-17')"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-310 aai-doctor CAT-17 reports not-armed (naming install-pre-commit-hook) on a hookless fixture and armed/PASS once installed"
}

# --- TEST-311 (Spec-AC-08) — this suite leaves $PROJECT_ROOT/.git/hooks alone
# Digest captured once at suite start (main(), before any test runs) and
# compared here at the end.
test_311_hooks_dir_unchanged() {
  local after
  after="$(manifest_of "$PROJECT_ROOT/.git/hooks")"
  if [[ "$after" == "$HOOKS_DIGEST_BEFORE" ]]; then
    log_pass "TEST-311 \$PROJECT_ROOT/.git/hooks is byte-unchanged across the whole suite run"
  else
    log_fail "TEST-311 \$PROJECT_ROOT/.git/hooks CHANGED during this suite run — every installer invocation above must target its own mktemp fixture"
  fi
}

# --- TEST-312 (Spec-AC-09) — canon surface + prompt-diet ---------------------
test_312_contract_and_diet() {
  local sc="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
  local ok=1
  if [[ ! -f "$sc" ]]; then
    log_fail "TEST-312: $sc not found"
    return
  fi
  grep -qF "AAI_GIT_WRITE" "$sc" || { log_fail "TEST-312: SUBAGENT_CONTRACT.md missing AAI_GIT_WRITE"; ok=0; }
  grep -qF "AAI:REF-GUARD" "$sc" || { log_fail "TEST-312: SUBAGENT_CONTRACT.md missing AAI:REF-GUARD"; ok=0; }

  local tok
  for tok in HAZ-RESTORE HAZ-SCRATCH HAZ-CD HAZ-LEDGER HAZ-WORKTREE; do
    grep -qF "$tok" "$sc" || { log_fail "TEST-312: SUBAGENT_CONTRACT.md missing hazard anchor $tok"; ok=0; }
  done
  for tok in fu-orchestrator-mutated-real-file fu-subagent-probe-hits-real-repo \
             fu-empty-path-cd-stays-in-shipping-repo fu-append-only-merge-needs-prefix-order \
             fu-prune-repair-error-string-misquoted; do
    grep -qF "$tok" "$sc" || { log_fail "TEST-312: SUBAGENT_CONTRACT.md missing scar citation $tok"; ok=0; }
  done

  local diet_out diet_rc
  diet_out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh 2>&1)"; diet_rc=$?
  if [[ $diet_rc -ne 0 ]]; then
    log_fail "TEST-312: test-aai-prompt-diet.sh exited $diet_rc"
    ok=0
  fi
  # The claim is "THIS ride did not move the corpus credit", not "the credit is
  # forever 2392". A literal turns every OTHER ride's honestly-paid growth into
  # a red arm here: merging the operator-waiver ride (2392 -> 2631, itemised in
  # the ledger) reddened this suite while nothing in this ride touched a prompt.
  # So the expectation is derived from the base branch's ledger instead.
  local base_pin live_pin base_ledger
  base_ledger="$TMP_ROOT/t312-base-ledger.sh"
  if (cd "$PROJECT_ROOT" && git show origin/main:tests/skills/lib/prompt-diet-ledger.sh) > "$base_ledger" 2>/dev/null \
     && [[ -s "$base_ledger" ]]; then
    # Derive the base credit with the ledger's OWN summation rather than a
    # reimplementation here: a second copy of that arithmetic would drift from
    # the real one and this arm would then be pinning its own bug.
    base_pin="$(bash -c 'set -e; . "$1" >/dev/null 2>&1; printf "%s" "$JUSTIFIED_GROWTH_BYTES"' _ "$base_ledger" 2>/dev/null)"
  fi
  live_pin="$(printf '%s\n' "$diet_out" | sed -n 's/.*JUSTIFIED_GROWTH_BYTES == \([-0-9][0-9]*\).*/\1/p' | head -1)"
  if [[ -z "$live_pin" ]]; then
    log_fail "TEST-312: prompt-diet output does not report JUSTIFIED_GROWTH_BYTES at all: $(printf '%s\n' "$diet_out" | grep -i justified | head -1)"
    ok=0
  elif [[ -z "${base_pin:-}" ]]; then
    log_info "TEST-312: origin/main's ledger is unreadable here; corpus-credit drift not checked this run"
  elif [[ "$live_pin" -ne "$base_pin" ]]; then
    log_fail "TEST-312: this ride moved the corpus credit ($base_pin on origin/main -> $live_pin here) — a prompt edit needs its own itemised ledger entry"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-312 SUBAGENT_CONTRACT.md names AAI_GIT_WRITE + AAI:REF-GUARD, all 5 HAZ anchors + 5 scar citations survive, and test-aai-prompt-diet.sh exits 0 with the corpus credit unmoved from origin/main"
}

# --- TEST-313 (Spec-AC-07) — LIVE, degrade-and-report ------------------------
# A safe, side-effect-free probe against $PROJECT_ROOT REGARDLESS of whether
# the guard is armed: `git update-ref refs/heads/main <sha> <sha>` names
# refs/heads/main at the 'prepared' state (measured) but is a true no-op
# (old value == new value), so even a bug that let it through moves nothing.
# We deliberately do NOT `git commit`/checkout main here — this ride stays on
# its own feature branch throughout (HARD boundary), and a feature-branch
# commit is the amended ALLOWED case anyway, which would prove nothing.
test_313_live_degrade_and_report() {
  local common
  common="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
  if [[ -z "$common" ]]; then
    log_named_skip "TEST-313 could not resolve \$PROJECT_ROOT's git common dir"
    return
  fi
  local gitdir="$common"
  [[ "$gitdir" = /* ]] || gitdir="$PROJECT_ROOT/$gitdir"
  local hook="$gitdir/hooks/reference-transaction"

  if [[ ! -f "$hook" ]] || ! grep -qF "AAI:REF-GUARD" "$hook"; then
    log_named_skip "TEST-313 ref-guard not armed on this checkout"
    return
  fi

  local mainsha; mainsha="$(git -C "$PROJECT_ROOT" rev-parse refs/heads/main 2>/dev/null)"
  if [[ -z "$mainsha" ]]; then
    log_named_skip "TEST-313 refs/heads/main not present on this checkout"
    return
  fi

  local before_head before_status
  before_head="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  before_status="$(git -C "$PROJECT_ROOT" status --porcelain=v1)"

  local out rc
  out="$(cd "$PROJECT_ROOT" && git update-ref refs/heads/main "$mainsha" "$mainsha" 2>&1)"; rc=$?

  local after_head after_status
  after_head="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  after_status="$(git -C "$PROJECT_ROOT" status --porcelain=v1)"

  local ok=1
  if [[ $rc -eq 0 ]]; then
    log_fail "TEST-313 LIVE: refs/heads/main no-op update expected non-zero (guard armed), got 0"
    ok=0
  fi
  if ! grep -q "AAI_GIT_WRITE" <<<"$out"; then
    log_fail "TEST-313 LIVE: stderr does not name AAI_GIT_WRITE: $out"
    ok=0
  fi
  if [[ "$before_head" != "$after_head" || "$before_status" != "$after_status" ]]; then
    log_fail "TEST-313 LIVE: HEAD or working-tree status changed by the refused probe"
    ok=0
  fi
  if [[ $ok -eq 1 ]]; then
    log_pass "TEST-313 LIVE degrade-and-report: the armed guard refuses a refs/heads/main update on \$PROJECT_ROOT; HEAD and status are byte-unchanged"
    mkdir -p "$PROJECT_ROOT/docs/ai/tdd"
    {
      echo "TEST-313 live transcript ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
      echo "hook: $hook"
      echo "command: git update-ref refs/heads/main $mainsha $mainsha"
      echo "exit: $rc"
      echo "--- stderr/stdout ---"
      echo "$out"
    } > "$PROJECT_ROOT/docs/ai/tdd/test-313-live-$(date -u +%Y%m%dT%H%M%SZ).log"
  fi
}

# --- TEST-316 - the .ps1 must stay ASCII outside its here-strings -------------
# Windows PowerShell 5.1 reads a UTF-8 file with no BOM in the SYSTEM CODE PAGE,
# so a multi-byte character inside a double-quoted string decodes into bytes that
# can close the quote early. Everything after it is then parsed as code - which
# is how a single em dash in one Write-Host message made 5.1 read the shell hook
# body as PowerShell and report "the token '||' is not a valid statement
# separator". pwsh 7 parses the same file cleanly, so this NEVER reproduces
# locally; CI's 5.1 leg is the only thing that sees it, and by then the errors
# point at the wrong lines entirely.
# Here-string CONTENT is exempt on purpose: it is data, never parsed, and it has
# to stay byte-identical to the .sh twin's hook body.
test_316_ps1_ascii_outside_here_strings() {
  local code
  code="$(awk '
    /^\$[A-Za-z]+ = @'"'"'$/ { inhere = 1; next }
    inhere && /^'"'"'@$/       { inhere = 0; next }
    inhere                     { next }
    { print }
  ' "$INSTALLER_PS1")"
  if [[ -z "$code" ]]; then
    log_fail "TEST-316: stripping here-strings left no code (the extraction shape moved)"
    return
  fi
  local offenders
  offenders="$(printf '%s\n' "$code" | LC_ALL=C grep -n '[^ -~\t]')" || offenders=""
  if [[ -n "$offenders" ]]; then
    log_fail "TEST-316: non-ASCII outside a here-string in $INSTALLER_PS1 - PowerShell 5.1 decodes it in the system code page and can end a string early: $offenders"
    return
  fi
  log_pass "TEST-316 .ps1 carries no non-ASCII outside its here-strings (5.1 code-page safe)"
}

main() {
  check_deps
  HOOKS_DIGEST_BEFORE="$(manifest_of "$PROJECT_ROOT/.git/hooks")"

  if [[ "${1:-}" != "" ]]; then
    local t="$1"
    if declare -f "test_${t}" >/dev/null 2>&1; then
      "test_${t}"
    else
      echo "Unknown test: $t" >&2
      exit 2
    fi
    echo ""
    if [[ $FAILED -eq 0 ]]; then
      echo "Selected test passed."
      exit 0
    else
      echo "Selected test FAILED."
      exit 1
    fi
  fi

  test_301_guarded_refusal
  test_302_mutation_proof
  test_303_unmutated_control
  test_304_marker_allows
  test_305_reads_unaffected
  test_306_allocator_seam
  test_307_clone_seam
  test_308_installer_contract
  test_315_effective_hooks_path
  test_314_print_flag
  test_309_ps1_twin_static
  test_310_doctor_category
  test_312_contract_and_diet
  test_313_live_degrade_and_report
  test_316_ps1_ascii_outside_here_strings
  test_311_hooks_dir_unchanged

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

main "$@"
