#!/usr/bin/env bash
#
# Test: SPEC spec-lessons-that-must-hold-downstream-are-guards — a lesson that
# must hold wherever AAI is installed is a GUARD in the vendored layer, not a
# note in LEARNED.md. TEST-001..006.
#
#   TEST-001  AGENTS carries the routing rule (Spec-AC-01)
#   TEST-002  aai-release.sh NAMES a merged PR with no rolled-up section (Spec-AC-02)
#   TEST-003  check-committed-scope catches the 2026-09-06 stale-path shape (Spec-AC-03)
#   TEST-004  matching blobs pass; untracked / non-repo degrade NAMED (Spec-AC-03)
#   TEST-005  SKILL_PR invokes the check before its push (Spec-AC-04)
#   TEST-006  every LEARNED entry is triaged, every guard id is an OPEN follow-up,
#             and no entry body was removed (Spec-AC-05)
#
# Fixtures only: TEST-002/003/004 build throwaway git repos under $TEST_DIR.
# The live repository is read, never written.

set -u
TEST_NAME="test-aai-learned-routing"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$PROJECT_ROOT/.aai/scripts/check-committed-scope.mjs"
RELEASE="$PROJECT_ROOT/.aai/scripts/aai-release.sh"
AGENTS="$PROJECT_ROOT/.aai/AGENTS.md"
LEARNED="$PROJECT_ROOT/docs/knowledge/LEARNED.md"
FOLLOWUPS="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"
command -v git  >/dev/null 2>&1 || log_skip "git not found"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-learned-routing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

mkrepo() { # $1 = dir
  # Round-7 (PR #378 Copilot, memory-class bare-origin-head-defaultbranch):
  # TEST-007's write_scope_gate_repo fixture hard-codes `main` into STATE
  # current_focus/code_review base_ref/head_ref, so the scratch repo's
  # initial branch must actually BE main regardless of the host's
  # `init.defaultBranch` — `-b main` on a git new enough to support it,
  # falling back to a config override for older git (same portable pattern
  # as test-aai-factory-report.sh / test-aai-live-status.sh).
  mkdir -p "$1" \
    && { git -C "$1" init -q -b main . 2>/dev/null || git -C "$1" -c init.defaultBranch=main init -q .; } \
    && git -C "$1" config user.email t@e.st && git -C "$1" config user.name t
}

# --- TEST-001 (Spec-AC-01): the routing rule is canon, and vendored -----------
test_001_agents_rule() {
  log_info "Test: AGENTS' Operator contract states where a lesson goes (TEST-001)..."
  [ -f "$AGENTS" ] || log_fail "TEST-001: $AGENTS missing"
  awk '/^### Operator contract/{f=1;next} /^### |^## /{if(f)exit} f' "$AGENTS" > "$TEST_DIR/contract.txt"
  [ -s "$TEST_DIR/contract.txt" ] || log_fail "TEST-001: no Operator contract section in AGENTS.md"
  grep -qi 'guard, not a note' "$TEST_DIR/contract.txt" \
    || log_fail "TEST-001: the contract must state the rule in those terms: $(head -3 "$TEST_DIR/contract.txt")"
  # BOTH halves, or the rule is only half a routing decision
  grep -qi 'vendored layer' "$TEST_DIR/contract.txt" || log_fail "TEST-001: the rule must name where a downstream lesson goes (the vendored layer)"
  grep -qi 'LEARNED' "$TEST_DIR/contract.txt" || log_fail "TEST-001: the rule must name what LEARNED.md is still for"
  grep -qi 'local' "$TEST_DIR/contract.txt" || log_fail "TEST-001: the rule must say LEARNED is for LOCAL matters"
  local n; n="$(wc -l < "$TEST_DIR/contract.txt" | tr -d ' ')"
  [ "$n" -le 40 ] || log_fail "TEST-001: the contract must stay within 40 lines, got $n"
  log_pass "the Operator contract routes a lesson to a guard, keeps LEARNED for local matters (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): a merged PR with no section is NAMED --------------
test_002_release_names_unlogged_pr() {
  log_info "Test: the release dry run names a PR merged since the tag with no rolled-up section (TEST-002)..."
  local d="$TEST_DIR/rel"; mkrepo "$d"
  mkdir -p "$d/.aai/scripts"
  cp "$RELEASE" "$d/.aai/scripts/aai-release.sh"
  # The second section is the DISCRIMINATOR for the two-token subject below.
  # It carries the TRUNCATED body text (`fix(z): a`) and NOT the number, so a
  # parser that cuts the body at the FIRST `(#` finds a match here and calls
  # #104 logged, while the correct parser — cutting at the LAST token — looks
  # for `fix(z): a (#12) thing`, finds nothing, and names it.
  printf '# Changelog\n\n## [unreleased] — feat(x): the logged one\n\n- did a thing (#101)\n\n## [unreleased] — an unrelated note\n\n- fix(z): a — mentioned, but this is not that PR\n\n' > "$d/CHANGELOG.md"
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm "base"
  git -C "$d" tag -a v0.0.1 -m v0.0.1
  # two merged PRs after the tag; only #101 has a section
  printf 'a\n' > "$d/a.txt"; git -C "$d" add a.txt; git -C "$d" commit -qm "feat(x): the logged one (#101)"
  printf 'b\n' > "$d/b.txt"; git -C "$d" add b.txt; git -C "$d" commit -qm "feat(y): the FORGOTTEN one (#102)"
  # A PR merged with GitHub's merge-commit strategy carries its number in a
  # different shape and used to be skipped in silence, while this block promised
  # to name EVERY merged PR since the tag (bot review, PR #349).
  printf 'c\n' > "$d/c.txt"; git -C "$d" add c.txt
  git -C "$d" commit -qm "Merge pull request #103 from goodwind-cz/some-branch"
  # a subject carrying two PR tokens must be matched on the LAST one, with the
  # body taken from before that same token — not truncated at the first
  printf 'e\n' > "$d/e.txt"; git -C "$d" add e.txt
  git -C "$d" commit -qm "fix(z): a (#12) thing (#104)"
  local out; out="$(cd "$d" && AAI_RELEASE_NO_REMOTE=1 bash .aai/scripts/aai-release.sh --dry-run 2>&1)"
  printf '%s' "$out" > "$TEST_DIR/rel.out"
  # Assert on the PRECONDITIONS BLOCK, not the whole output: the notes preview
  # legitimately contains "(#101)", so a whole-output grep would fail the
  # false-positive arm for the wrong reason (it did, on the first run).
  awk '/^## Preconditions/{f=1;next} /^## /{f=0} f' "$TEST_DIR/rel.out" > "$TEST_DIR/rel.pre"
  [ -s "$TEST_DIR/rel.pre" ] || log_fail "TEST-002: no Preconditions block in the dry run: $(tail -20 "$TEST_DIR/rel.out")"
  grep -q '#102' "$TEST_DIR/rel.pre" \
    || log_fail "TEST-002: the unlogged PR #102 must be NAMED under Preconditions: $(cat "$TEST_DIR/rel.pre")"
  grep -q '#103' "$TEST_DIR/rel.pre" \
    || log_fail "TEST-002: a PR merged as a MERGE COMMIT must be named too, not skipped in silence: $(cat "$TEST_DIR/rel.pre")"
  grep -q '#104' "$TEST_DIR/rel.pre" \
    || log_fail "TEST-002: a subject carrying two PR tokens must be read on the LAST one: $(cat "$TEST_DIR/rel.pre")"
  grep -q 'NAMED (not blocking)' "$TEST_DIR/rel.pre" \
    || log_fail "TEST-002: it must be reported as named-not-blocking, never as a block"
  grep -q '#101' "$TEST_DIR/rel.pre" \
    && log_fail "TEST-002: the LOGGED PR #101 must not be named — that would be a false positive on every release"
  # and it must not turn a clean cut into a blocked one
  grep -q 'would block' "$TEST_DIR/rel.pre" \
    && log_fail "TEST-002: an unlogged PR must not block the cut"
  # the complete case: with BOTH logged, the block says exactly "none"
  printf '# Changelog\n\n## [unreleased] — feat(x): the logged one\n\n- did a thing (#101)\n\n## [unreleased] — feat(y): the FORGOTTEN one\n\n- and another (#102)\n\n## [unreleased] — the merge-commit one\n\n- merged the other way (#103)\n\n## [unreleased] — the two-token one\n\n- carried two numbers (#104)\n\n' > "$d/CHANGELOG.md"
  git -C "$d" add CHANGELOG.md >/dev/null && git -C "$d" commit -qm "chore: log both"
  out="$(cd "$d" && AAI_RELEASE_NO_REMOTE=1 bash .aai/scripts/aai-release.sh --dry-run 2>&1)"
  printf '%s' "$out" | awk '/^## Preconditions/{f=1;next} /^## /{f=0} f' > "$TEST_DIR/rel.pre2"
  grep -q 'NAMED (not blocking)' "$TEST_DIR/rel.pre2" \
    && log_fail "TEST-002: with every merged PR logged, nothing may be named: $(cat "$TEST_DIR/rel.pre2")"
  grep -q 'none — ready to cut' "$TEST_DIR/rel.pre2" \
    || log_fail "TEST-002: a complete cut must report no preconditions: $(cat "$TEST_DIR/rel.pre2")"
  log_pass "the release dry run names the unlogged PRs (squash, merge-commit and two-token subjects) and does not block (TEST-002)"
}

# --- TEST-003 (Spec-AC-03): the exact 2026-09-06 shape ------------------------
test_003_stale_add_shape() {
  log_info "Test: a frontmatter stamp left out of the commit by a stale-path add is caught (TEST-003)..."
  local d="$TEST_DIR/blob"; mkrepo "$d"
  printf -- '---\nid: x\nnumber: null\n---\n' > "$d/CHANGE-DRAFT-x.md"
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm base
  # the allocator renames and stages the rename itself...
  git -C "$d" mv CHANGE-DRAFT-x.md CHANGE-0042-x.md
  # ...and stamps the number in the WORKTREE
  printf -- '---\nid: x\nnumber: 42\n---\n' > "$d/CHANGE-0042-x.md"
  # the author then adds the OLD path: the whole add aborts, the stamp is lost
  ( cd "$d" && git add CHANGE-DRAFT-x.md >/dev/null 2>&1 ) || true
  local rc=0
  ( cd "$d" && node "$CHECK" CHANGE-0042-x.md > "$TEST_DIR/b.out" 2> "$TEST_DIR/b.err" ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-003: a lost stamp must exit 1, got $rc ($(cat "$TEST_DIR/b.out" "$TEST_DIR/b.err"))"
  grep -q 'CHANGE-0042-x.md' "$TEST_DIR/b.err" || log_fail "TEST-003: the refusal must NAME the path: $(cat "$TEST_DIR/b.err")"
  grep -qi 'already renamed' "$TEST_DIR/b.err" || log_fail "TEST-003: the message must explain the usual cause, so the reader can act"
  # git status alone cannot tell this apart — the reason the check exists
  local st; st="$(cd "$d" && git status --porcelain -- CHANGE-0042-x.md | cut -c1-2)"
  [ -n "$st" ] || log_fail "TEST-003: precondition — git status should show something here"
  log_pass "the stale-path add is caught and named; git status alone showed only '$st' (TEST-003)"
}

# --- TEST-004 (Spec-AC-03): clean passes, absences degrade NAMED --------------
test_004_clean_and_degrades() {
  log_info "Test: matching blobs pass; untracked and non-repo degrade with a name, never silently (TEST-004)..."
  local d="$TEST_DIR/clean"; mkrepo "$d"
  printf 'same\n' > "$d/f.txt"; git -C "$d" add f.txt; git -C "$d" commit -qm base
  local rc=0
  ( cd "$d" && node "$CHECK" f.txt > "$TEST_DIR/c.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-004: matching blobs must exit 0, got $rc: $(cat "$TEST_DIR/c.out")"
  grep -q 'clean' "$TEST_DIR/c.out" || log_fail "TEST-004: a clean run must say so"
  # a trailing-newline difference IS a difference (byte comparison)
  printf 'same' > "$d/f.txt"
  rc=0; ( cd "$d" && node "$CHECK" f.txt >/dev/null 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-004: a trailing-newline-only difference must be caught (byte comparison), got $rc"
  git -C "$d" checkout -- f.txt
  # untracked in-scope path: degrade, exit 0, and SAY it
  printf 'new\n' > "$d/untracked.txt"
  rc=0; ( cd "$d" && node "$CHECK" untracked.txt > "$TEST_DIR/u.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-004: an untracked path must degrade to 0, got $rc"
  grep -qi 'degraded' "$TEST_DIR/u.out" || log_fail "TEST-004: the degrade must be named, not silent: $(cat "$TEST_DIR/u.out")"
  grep -q 'untracked.txt' "$TEST_DIR/u.out" || log_fail "TEST-004: the degrade must name the path"
  # outside a git repo: degrade, exit 0, and say why
  local nr="$TEST_DIR/notrepo"; mkdir -p "$nr"; printf 'x\n' > "$nr/f.txt"
  rc=0; ( cd "$nr" && node "$CHECK" f.txt > "$TEST_DIR/n.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-004: outside a repo must degrade to 0, got $rc"
  grep -qi 'not a git repository' "$TEST_DIR/n.out" || log_fail "TEST-004: the non-repo degrade must say why: $(cat "$TEST_DIR/n.out")"
  # --from-state must read a FOLDED scope. state.mjs writes long values as
  # `scope: >-` with the text on the following lines; reading the header alone
  # yields ">-" and the check then verifies a path by that name — which is what
  # the first draft of this script did. Third block-scalar trap of the session.
  local sd="$TEST_DIR/state"; mkrepo "$sd"; mkdir -p "$sd/docs/ai"
  printf 'one\n' > "$sd/one.txt"; printf 'two\n' > "$sd/two.txt"
  git -C "$sd" add one.txt two.txt >/dev/null && git -C "$sd" commit -qm base
  printf 'code_review:\n  required: true\n  status: pass\n  scope: >-\n    one.txt,two.txt\n  base_ref: main\n' > "$sd/docs/ai/STATE.yaml"
  rc=0; ( cd "$sd" && node "$CHECK" --from-state --json > "$TEST_DIR/s.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-004: --from-state on a clean tree must exit 0, got $rc: $(cat "$TEST_DIR/s.out")"
  local n; n="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(d.checked))' "$TEST_DIR/s.out")"
  [ "$n" = "2" ] || log_fail "TEST-004: a folded scope must yield BOTH paths, checked=$n: $(cat "$TEST_DIR/s.out")"
  grep -q '>-' "$TEST_DIR/s.out" && log_fail "TEST-004: the block-scalar header must never be read as a path: $(cat "$TEST_DIR/s.out")"
  # and it still catches a real mismatch through that path
  printf 'changed\n' > "$sd/two.txt"
  rc=0; ( cd "$sd" && node "$CHECK" --from-state > "$TEST_DIR/s2.out" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-004: --from-state must still catch a mismatch, got $rc"
  grep -q 'two.txt' "$TEST_DIR/s2.out" || log_fail "TEST-004: the mismatch through --from-state must name the path"
  # A DIFF RANGE is a documented scope form (PLANNING.prompt.md: "explicit
  # paths or diff range"). Read as a filename it yields nothing checked, and
  # --strict then blocks the PR AFTER the commit was made — bot review, PR #349.
  local rg="$TEST_DIR/range"; mkrepo "$rg"; mkdir -p "$rg/docs/ai"
  printf 'a\n' > "$rg/a.txt"; printf 'b\n' > "$rg/b.txt"
  git -C "$rg" add a.txt b.txt >/dev/null && git -C "$rg" commit -qm base
  # The base is captured as a SHA, never as the name `main`. init.defaultBranch
  # is the runner's business — the branch is `master` on some hosts and the
  # range then names a ref that does not exist, which is a CI-only red (it was,
  # on PR #349; same family as the bare-origin HEAD trap).
  local base_sha; base_sha="$(git -C "$rg" rev-parse HEAD)"
  git -C "$rg" checkout -q -b work
  printf 'a2\n' > "$rg/a.txt"; git -C "$rg" add a.txt >/dev/null && git -C "$rg" commit -qm change
  printf 'code_review:\n  required: true\n  scope: >-\n    %s...HEAD\n  base_ref: %s\n' "$base_sha" "$base_sha" > "$rg/docs/ai/STATE.yaml"
  rc=0; ( cd "$rg" && node "$CHECK" --from-state --strict --rev HEAD --json > "$TEST_DIR/rg.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-004: a diff-range scope must expand and pass on a clean tree, got $rc: $(cat "$TEST_DIR/rg.out")"
  local rn; rn="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(d.checked))' "$TEST_DIR/rg.out")"
  [ "$rn" = "1" ] || log_fail "TEST-004: the range must expand to the ONE path it names, checked=$rn: $(cat "$TEST_DIR/rg.out")"
  grep -q "$base_sha\.\.\.HEAD" "$TEST_DIR/rg.out" && log_fail "TEST-004: the range itself must never be treated as a path: $(cat "$TEST_DIR/rg.out")"
  # and it still catches a real gap through that form
  printf 'a3\n' > "$rg/a.txt"
  rc=0; ( cd "$rg" && node "$CHECK" --from-state --strict --rev HEAD > "$TEST_DIR/rg2.out" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-004: an uncommitted edit must still fail through a range scope, got $rc"
  grep -q 'a.txt' "$TEST_DIR/rg2.out" || log_fail "TEST-004: the mismatch through a range must name the path"
  log_pass "clean passes; newline difference caught; untracked and non-repo degrade named; a folded scope reads both paths; a diff-range scope expands (TEST-004)"
}

# --- TEST-005 (Spec-AC-04): the ceremony actually runs it ---------------------
test_005_skill_pr_wiring() {
  log_info "Test: SKILL_PR invokes the check before its push and states the STOP (TEST-005)..."
  local f="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  grep -q 'check-committed-scope.mjs' "$f" || log_fail "TEST-005: SKILL_PR must invoke check-committed-scope.mjs"
  # --strict, or a path missing from the commit degrades to exit 0 and the gate
  # waves through the very incident it was written for
  grep -q 'check-committed-scope.mjs --from-state --strict --rev HEAD' "$f" \
    || log_fail "TEST-005: SKILL_PR must invoke the check with --strict --rev HEAD — the default compares the INDEX, and this step is about the COMMIT"
  # and the guard must genuinely tell the two apart: a path staged after the
  # commit but never committed is clean against the index and DIRTY against HEAD
  local rv="$TEST_DIR/rev"; mkrepo "$rv"
  printf 'v1\n' > "$rv/doc.md"; git -C "$rv" add doc.md >/dev/null; git -C "$rv" commit -qm base
  printf 'v2\n' > "$rv/doc.md"; git -C "$rv" add doc.md >/dev/null
  rc=0; ( cd "$rv" && node "$CHECK" doc.md --strict >/dev/null 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-005: staged-and-matching must be clean against the INDEX, got $rc"
  rc=0; ( cd "$rv" && node "$CHECK" doc.md --strict --rev HEAD > "$TEST_DIR/rev.out" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-005: a path staged but never committed must FAIL against HEAD, got $rc: $(cat "$TEST_DIR/rev.out")"
  grep -q 'doc.md' "$TEST_DIR/rev.out" || log_fail "TEST-005: the HEAD mismatch must name the path"
  # ORDER IS THE WHOLE POINT. The first draft placed this step before staging,
  # where nothing is in the index yet: it then reported every ordinary edit as a
  # mismatch, and its own remedy — amend — had no commit to amend. So the
  # assertion is commit < check < push, not merely check < push. The earlier
  # version compared against the LAST push mention in the file and was therefore
  # true for any placement in the first 236 lines (code review, 2026-09-06).
  local ci pi mi
  ci="$(grep -n 'check-committed-scope.mjs' "$f" | head -1 | cut -d: -f1)"
  mi="$(grep -nE '^4\. COMMIT' "$f" | head -1 | cut -d: -f1)"
  pi="$(grep -nE '^5\. PLATFORM GATE \+ PUSH' "$f" | head -1 | cut -d: -f1)"
  [ -n "$ci" ] && [ -n "$mi" ] && [ -n "$pi" ] \
    || log_fail "TEST-005: could not locate the check ($ci), the COMMIT step ($mi) and the PUSH step ($pi)"
  [ "$mi" -lt "$ci" ] \
    || log_fail "TEST-005: the check (line $ci) must come AFTER the commit (line $mi) — before it, nothing is staged and every edit reads as a mismatch"
  [ "$ci" -lt "$pi" ] \
    || log_fail "TEST-005: the check (line $ci) must precede the push (line $pi)"
  # the STOP sentence must live in the check's OWN block, not anywhere in a file
  # that already said "stop" 18 times before this scope existed
  # awk into a FILE, then grep the file: piping a variable into `grep -q` is the
  # 64 KiB SIGPIPE defect this repo already has a guard for (test_102).
  awk -v s="$ci" 'NR>=s-6 && NR<=s+14' "$f" > "$TEST_DIR/pr-block.txt"
  grep -q 'STOP' "$TEST_DIR/pr-block.txt" \
    || log_fail "TEST-005: the STOP must be stated in the check's own block, not merely somewhere in the file"
  log_pass "SKILL_PR runs the committed-scope check with --strict, after the commit and before the push (TEST-005)"
}

# --- TEST-006 (Spec-AC-05): the triage is complete and honest -----------------
test_006_learned_triaged() {
  log_info "Test: every LEARNED entry is triaged, guard ids are OPEN follow-ups, nothing was deleted (TEST-006)..."
  [ -f "$LEARNED" ] || log_fail "TEST-006: $LEARNED missing"
  grep -qi 'guard' "$LEARNED" || log_fail "TEST-006: the header must state the routing rule"
  local total tagged
  total="$(grep -c '^- \[20' "$LEARNED" | tr -d ' ')"
  # A guard marker names EITHER the follow-up that will build the guard, OR a
  # guard that already exists (a script in the vendored layer). Requiring a
  # follow-up for a guard already shipped would force a fake open item.
  tagged="$(grep -cE '^- \[20[0-9]{2}-[0-9]{2}-[0-9]{2}\] \[(local|guard → (fu-[a-z0-9-]+|[a-z0-9.-]+\.(mjs|sh|ps1)))\]' "$LEARNED" | tr -d ' ')"
  [ "$total" = "$tagged" ] || log_fail "TEST-006: all $total entries must carry exactly one [local] or [guard → …] marker, $tagged do"
  # a follow-up id must resolve to an OPEN item
  node "$FOLLOWUPS" list --status open > "$TEST_DIR/open.txt" 2>&1 || log_fail "TEST-006: follow-ups list failed"
  local missing=""
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    grep -qF -- "$id" "$TEST_DIR/open.txt" || missing="$missing $id"
  done <<EOF
$(grep -oE 'guard → fu-[a-z0-9-]+' "$LEARNED" | sed 's/^guard → //' | sort -u)
EOF
  [ -z "$missing" ] || log_fail "TEST-006: guard marker(s) name follow-ups that are not open:$missing"
  # a named script must actually exist, or the pointer is a dead end
  local absent=""
  while IFS= read -r sc; do
    [ -n "$sc" ] || continue
    [ -f "$PROJECT_ROOT/.aai/scripts/$sc" ] || absent="$absent $sc"
  done <<EOF
$(grep -oE 'guard → [a-z0-9.-]+\.(mjs|sh|ps1)' "$LEARNED" | sed 's/^guard → //' | sort -u)
EOF
  [ -z "$absent" ] || log_fail "TEST-006: guard marker(s) name a script that does not exist:$absent"

  # NOTHING WAS DELETED. Spec-AC-05's second half. The count above is derived
  # from the file it validates, so on its own it cannot see a deletion: removing
  # an entry outright keeps total == tagged and ships green — verified by
  # validation, which deleted the 2026-08-07 entry and watched this test PASS.
  # The pin is an immutable commit, never a moving ref: an equality pinned
  # against origin/main rots for everyone on the next merge (LEARNED 2026-09-05).
  # RE-PINNING. The body comparison below strips only the DATE prefix from the
  # pinned base, so it is correct while the base is marker-free. Re-pin to a
  # commit that already carries `[local]` / `[guard → …]` markers and then
  # re-mark an entry, and the fixed-string search will report a deletion that
  # did not happen — strip the marker too, in that case.
  local BASE_LEARNED_PIN=9296160c5e89900fd2f754daf80c660c2521ec75
  local BASE_LEARNED_ENTRIES=15
  if git -C "$PROJECT_ROOT" cat-file -e "$BASE_LEARNED_PIN:docs/knowledge/LEARNED.md" 2>/dev/null; then
    git -C "$PROJECT_ROOT" show "$BASE_LEARNED_PIN:docs/knowledge/LEARNED.md" > "$TEST_DIR/learned.base" 2>/dev/null \
      || log_fail "TEST-006: could not read the pinned base LEARNED.md"
    local base_n
    base_n="$(grep -c '^- \[20' "$TEST_DIR/learned.base" | tr -d ' ')"
    [ "$base_n" = "$BASE_LEARNED_ENTRIES" ] \
      || log_fail "TEST-006: the pinned base must hold $BASE_LEARNED_ENTRIES entries, it holds $base_n — re-pin deliberately, do not adjust the number to match"
    [ "$total" -ge "$BASE_LEARNED_ENTRIES" ] \
      || log_fail "TEST-006: LEARNED.md now holds $total entries, fewer than the $BASE_LEARNED_ENTRIES it held at $BASE_LEARNED_PIN — an entry was deleted"
    # every pre-edit entry BODY must still occur verbatim. The body is the entry
    # text after this scope's marker was inserted, so the comparison strips the
    # date prefix and compares the remainder as a fixed string.
    local gone=0 first=""
    while IFS= read -r body; do
      [ -n "$body" ] || continue
      if ! grep -qF -- "$body" "$LEARNED"; then
        gone=$((gone + 1)); [ -n "$first" ] || first="$body"
      fi
    done <<EOF
$(sed -n 's/^- \[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] //p' "$TEST_DIR/learned.base")
EOF
    [ "$gone" -eq 0 ] \
      || log_fail "TEST-006: $gone pre-edit entry body/bodies no longer occur in LEARNED.md — the triage may mark entries, never remove them. First: ${first:0:70}"
  else
    log_info "TEST-006: base commit $BASE_LEARNED_PIN not present (shallow clone) — the no-deletion half is SKIPPED, not silently passed"
  fi
  log_pass "all $total entries triaged; guard pointers resolve; no pre-edit entry body was removed (TEST-006)"
}

# --- TEST-007 (Spec-AC-09): check-committed-scope uses a preserved scope only
# when scope_ref_id agrees with current_focus.ref_id ------------------------
#
# write_scope_gate_repo <dir> <focus_ref> — a git repo + STATE.yaml driven
# through a REAL metrics-flush.mjs partial reset (S4: never a synthesized
# STATE), differing only in current_focus.ref_id (CHANGE-0001, the ref that
# flushes, vs CHANGE-0002, the ref that stays active).
write_scope_gate_repo() {
  local d="$1" focus_ref="$2"
  mkrepo "$d"
  mkdir -p "$d/docs/ai"
  printf 'x\n' > "$d/a.txt"
  git -C "$d" add a.txt >/dev/null && git -C "$d" commit -qm base >/dev/null
  cat > "$d/pricing.yaml" <<'YAML'
schema_version: 2
lookup_rules:
  order:
    - exact-match
    - unknown-fallback
models:
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
  : > "$d/docs/ai/LOOP_TICKS.jsonl"
  cat > "$d/docs/ai/STATE.yaml" <<STATE
project_status: active
current_focus:
  type: intake_change
  ref_id: $focus_ref
  primary_path: null
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
    primary_path: null
  - ref_id: CHANGE-0002
    status: in_progress
    phase: implementation
    primary_path: null
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: true
  status: pass
  scope: >-
    a.txt
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: pass
  run_at_utc: 2026-07-15T10:00:00Z
  ref_id: CHANGE-0001
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
tdd_cycle:
  status: IDLE
  test_id: null
  spec_path: null
  test_path: null
  evidence:
    red: null
    green: null
    refactor: null
metrics:
  work_items:
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-test
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
    CHANGE-0002:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-test
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null

updated_at_utc: 2026-07-15T09:30:00Z
STATE
  ( cd "$d" && node "$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs" \
      --state docs/ai/STATE.yaml --metrics docs/ai/METRICS.jsonl \
      --ticks docs/ai/LOOP_TICKS.jsonl --pricing pricing.yaml \
      --events docs/ai/EVENTS.jsonl --now 2026-07-15T10:00:00Z \
      > flush.out 2>&1 ) || log_fail "fixture flush must exit 0: $(cat "$d/flush.out")"
}

test_007_scope_ref_id_gate() {
  log_info "Test: check-committed-scope --from-state uses a preserved scope only when scope_ref_id matches current_focus.ref_id, degrades naming both refs otherwise, and behaves as today when scope_ref_id is absent (TEST-007, seam S4)..."
  local rc

  # (a) matching: current_focus.ref_id equals the flushed ref -> scope USED.
  local a="$TEST_DIR/t007a"
  write_scope_gate_repo "$a" CHANGE-0001
  grep -qE '^  scope_ref_id: CHANGE-0001$' "$a/docs/ai/STATE.yaml" \
    || log_fail "(a) fixture setup: the real partial-flush reset must have stamped scope_ref_id CHANGE-0001: $(cat "$a/docs/ai/STATE.yaml")"
  rc=0; ( cd "$a" && node "$CHECK" --from-state --json > "$TEST_DIR/a.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "(a) matching scope_ref_id must exit 0, got $rc: $(cat "$TEST_DIR/a.out")"
  local n; n="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(d.checked))' "$TEST_DIR/a.out")"
  [ "$n" = "1" ] || log_fail "(a) the preserved scope must be USED (one path, a.txt), checked=$n: $(cat "$TEST_DIR/a.out")"
  grep -qi 'scope_ref_id' "$TEST_DIR/a.out" && log_fail "(a) a matching scope_ref_id must never degrade: $(cat "$TEST_DIR/a.out")"

  # (b) mismatching: current_focus.ref_id names the OTHER (still-active) ref
  # -> the preserved scope is a DIFFERENT ride's and must NOT be reused.
  local b="$TEST_DIR/t007b"
  write_scope_gate_repo "$b" CHANGE-0002
  rc=0; ( cd "$b" && node "$CHECK" --from-state --json > "$TEST_DIR/b.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "(b) a mismatched scope_ref_id must DEGRADE (exit 0, never a hard failure), got $rc: $(cat "$TEST_DIR/b.out")"
  grep -qi 'scope_ref_id' "$TEST_DIR/b.out" || log_fail "(b) the degrade must name scope_ref_id: $(cat "$TEST_DIR/b.out")"
  grep -qF 'CHANGE-0001' "$TEST_DIR/b.out" || log_fail "(b) the degrade must name the STATE's scope_ref_id (CHANGE-0001): $(cat "$TEST_DIR/b.out")"
  grep -qF 'CHANGE-0002' "$TEST_DIR/b.out" || log_fail "(b) the degrade must name the current ride's ref (CHANGE-0002): $(cat "$TEST_DIR/b.out")"
  local n2; n2="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(d.checked))' "$TEST_DIR/b.out")"
  [ "$n2" = "0" ] || log_fail "(b) a degraded (unused) scope must check nothing, checked=$n2: $(cat "$TEST_DIR/b.out")"

  # (c) scope_ref_id ABSENT (legacy STATE, back-compat) -> behaves exactly as
  # today: the scope is used with no mismatch degrade (already covered by
  # TEST-004's own --from-state fixture, which never carries the field —
  # asserted again here for this seam's own record).
  local cdir="$TEST_DIR/t007c"; mkrepo "$cdir"; mkdir -p "$cdir/docs/ai"
  printf 'one\n' > "$cdir/one.txt"
  git -C "$cdir" add one.txt >/dev/null && git -C "$cdir" commit -qm base >/dev/null
  printf 'code_review:\n  required: true\n  status: pass\n  scope: >-\n    one.txt\n  base_ref: main\n' > "$cdir/docs/ai/STATE.yaml"
  rc=0; ( cd "$cdir" && node "$CHECK" --from-state --json > "$TEST_DIR/c.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "(c) an absent scope_ref_id must behave exactly as today, got $rc: $(cat "$TEST_DIR/c.out")"
  grep -qi 'scope_ref_id' "$TEST_DIR/c.out" && log_fail "(c) an absent scope_ref_id must never trigger the degrade: $(cat "$TEST_DIR/c.out")"

  # (d) NON-BLOCKING-A fix (review-telemetry-fields-not-prose-20260913T105322Z):
  # a freshly-set scope from set-code-review REFRESHES scope_ref_id to the
  # CURRENT current_focus.ref_id, so a scope set for THIS ride is USED even
  # though an OLDER flush stamped a DIFFERENT ref's scope_ref_id.
  local dd="$TEST_DIR/t007d"
  write_scope_gate_repo "$dd" CHANGE-0002
  grep -qE '^  scope_ref_id: CHANGE-0001$' "$dd/docs/ai/STATE.yaml" \
    || log_fail "(d) fixture setup: the older flush must have stamped scope_ref_id CHANGE-0001: $(cat "$dd/docs/ai/STATE.yaml")"
  ( cd "$dd" && node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-code-review --scope a.txt --state docs/ai/STATE.yaml > "$TEST_DIR/d.setscope.out" 2>&1 ) \
    || log_fail "(d) set-code-review --scope must exit 0: $(cat "$TEST_DIR/d.setscope.out")"
  grep -qE '^  scope_ref_id: CHANGE-0002$' "$dd/docs/ai/STATE.yaml" \
    || log_fail "(d) set-code-review --scope must REFRESH scope_ref_id to the current focus ref (CHANGE-0002), not leave the older stamp: $(cat "$dd/docs/ai/STATE.yaml")"
  rc=0; ( cd "$dd" && node "$CHECK" --from-state --json > "$TEST_DIR/d.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "(d) a freshly-set scope must exit 0, got $rc: $(cat "$TEST_DIR/d.out")"
  local nd; nd="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(d.checked))' "$TEST_DIR/d.out")"
  [ "$nd" = "1" ] || log_fail "(d) a freshly set scope must be USED even though an older flush stamped a different ref, checked=$nd: $(cat "$TEST_DIR/d.out")"
  grep -qi 'scope_ref_id' "$TEST_DIR/d.out" && log_fail "(d) a freshly refreshed scope_ref_id must never degrade: $(cat "$TEST_DIR/d.out")"

  log_pass "check-committed-scope uses a preserved scope only when scope_ref_id agrees, degrades naming both refs otherwise, unchanged when absent, and a fresh set-code-review scope refreshes the stamp (TEST-007)"
}

# --- TEST-008 (Spec-AC-17 / dispatch-state-sweep D15): append vs divergence ---
test_008_ledger_append_vs_divergence() {
  log_info "Test: an append-only ledger growing at its own end reports an append and does not fail; a rewritten middle line reports a divergence and fails; a non-ledger path is unchanged in both shapes; an empty committed blob is an append (TEST-008)..."
  local d="$TEST_DIR/ledger"; mkrepo "$d"
  mkdir -p "$d/docs/ai/tests"

  # (a) EVENTS.jsonl grows at its own end -> append, exit 0, not a failure.
  printf '{"n":1}\n{"n":2}\n' > "$d/docs/ai/EVENTS.jsonl"
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm base
  printf '{"n":3}\n{"n":4}\n{"n":5}\n' >> "$d/docs/ai/EVENTS.jsonl"
  local rc=0
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl --json > "$TEST_DIR/append.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-008: (a) an append-only ledger growing at its own end must exit 0, got $rc: $(cat "$TEST_DIR/append.out")"
  grep -q '"status": "clean"' "$TEST_DIR/append.out" \
    || log_fail "TEST-008: (a) status must still be clean (an append is not a failure): $(cat "$TEST_DIR/append.out")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (o.appends.length !== 1) { console.error("expected exactly one append entry, got " + JSON.stringify(o.appends)); process.exit(1); }
    if (o.appends[0].path !== "docs/ai/EVENTS.jsonl") { console.error("wrong path: " + JSON.stringify(o.appends[0])); process.exit(1); }
    if (o.appends[0].added_lines !== 3) { console.error("expected added_lines 3, got " + JSON.stringify(o.appends[0])); process.exit(1); }
    if (o.mismatches.length !== 0) { console.error("an append must never land in mismatches: " + JSON.stringify(o.mismatches)); process.exit(1); }
  ' "$TEST_DIR/append.out" || log_fail "TEST-008: (a) the append entry must name the path and the exact added line count (3)"
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl > "$TEST_DIR/append-plain.out" 2>&1 )
  grep -qi 'append' "$TEST_DIR/append-plain.out" \
    || log_fail "TEST-008: (a) plain-text output must name the append: $(cat "$TEST_DIR/append-plain.out")"

  # (b) SAME committed base, but the worktree REWRITES an earlier line instead
  # of only growing at the end -> divergence, exit 1, a real failure.
  printf '{"n":1}\n{"n":2, "rewritten": true}\n{"n":3}\n' > "$d/docs/ai/EVENTS.jsonl"
  rc=0
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl --json > "$TEST_DIR/diverge.out" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-008: (b) a rewritten middle line must exit 1, got $rc: $(cat "$TEST_DIR/diverge.out")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (o.appends.length !== 0) { console.error("a divergence must never be reported as an append: " + JSON.stringify(o.appends)); process.exit(1); }
    if (o.mismatches.indexOf("docs/ai/EVENTS.jsonl") === -1) { console.error("the divergence must land in mismatches: " + JSON.stringify(o.mismatches)); process.exit(1); }
  ' "$TEST_DIR/diverge.out" || log_fail "TEST-008: (b) a rewritten middle line must report as a divergence, not an append"
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl > "$TEST_DIR/diverge-plain.out" 2>&1 ) || true
  grep -qi 'divergence' "$TEST_DIR/diverge-plain.out" \
    || log_fail "TEST-008: (b) plain-text output must name the divergence: $(cat "$TEST_DIR/diverge-plain.out")"
  git -C "$d" checkout -q -- docs/ai/EVENTS.jsonl

  # (c) a NON-ledger path growing at its own end behaves EXACTLY as today —
  # a plain mismatch, never an append. Ledger treatment is a closed list, not
  # a general append heuristic.
  printf 'one\n' > "$d/notes.txt"
  git -C "$d" add notes.txt >/dev/null && git -C "$d" commit -qm "add notes"
  printf 'one\ntwo\n' > "$d/notes.txt"
  rc=0
  ( cd "$d" && node "$CHECK" notes.txt --json > "$TEST_DIR/nonledger.out" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-008: (c) a non-ledger path growing at its own end must still fail exactly as today, got $rc: $(cat "$TEST_DIR/nonledger.out")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (o.appends.length !== 0) { console.error("a non-ledger path must never be reported as an append: " + JSON.stringify(o.appends)); process.exit(1); }
    if (o.mismatches.indexOf("notes.txt") === -1) { console.error("the non-ledger growth must land in mismatches: " + JSON.stringify(o.mismatches)); process.exit(1); }
  ' "$TEST_DIR/nonledger.out" || log_fail "TEST-008: (c) a non-ledger path is unaffected by D15 — it fails exactly as today"
  git -C "$d" checkout -q -- notes.txt

  # (d) an EMPTY committed blob -> every worktree byte is an append.
  : > "$d/docs/ai/decisions.jsonl"
  git -C "$d" add docs/ai/decisions.jsonl >/dev/null && git -C "$d" commit -qm "empty ledger"
  printf '{"n":1}\n' > "$d/docs/ai/decisions.jsonl"
  rc=0
  ( cd "$d" && node "$CHECK" docs/ai/decisions.jsonl --json > "$TEST_DIR/empty.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-008: (d) an empty committed blob must treat the whole worktree as an append, got $rc: $(cat "$TEST_DIR/empty.out")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (o.appends.length !== 1 || o.appends[0].added_lines !== 1) { console.error("expected one append of 1 line: " + JSON.stringify(o.appends)); process.exit(1); }
  ' "$TEST_DIR/empty.out" || log_fail "TEST-008: (d) an empty committed blob's whole worktree content must be the append"

  log_pass "a ledger growing at its own end reports an append (never a failure); a rewritten middle line reports a divergence (a real failure); a non-ledger path is unchanged; an empty committed blob is an append (TEST-008)"
}

# --- TEST-010 (Round 6, Codex P1): --strict --rev HEAD rejects an uncommitted
# ledger append instead of waving it through as benign ---
test_010_strict_rejects_pending_append() {
  log_info "Test: --strict --rev HEAD reports an unstaged HAZ-LEDGER append as a MISMATCH named 'pending append not committed' and exits non-zero; the SAME append under non-strict stays a clean advisory append (TEST-010)..."
  local d="$TEST_DIR/pending-append"; mkrepo "$d"
  mkdir -p "$d/docs/ai"
  printf '{"n":1}\n{"n":2}\n' > "$d/docs/ai/EVENTS.jsonl"
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm base
  # A ledger record left OUT of the commit — the exact shape the PR finding
  # named: docs/ai/decisions.jsonl or test-runs.jsonl growing on disk with
  # HEAD not yet carrying it.
  printf '{"n":3}\n' >> "$d/docs/ai/EVENTS.jsonl"

  # (a) non-strict --rev HEAD: unchanged — advisory append, exit 0, never a
  # mismatch. Strict is the only mode this fix changes.
  local rc=0
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl --rev HEAD --json > "$TEST_DIR/pa-nonstrict.out" 2>&1 ) || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-010: (a) non-strict --rev HEAD must still exit 0 on an append, got $rc: $(cat "$TEST_DIR/pa-nonstrict.out")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (o.mismatches.length !== 0) { console.error("non-strict must never fail an append: " + JSON.stringify(o.mismatches)); process.exit(1); }
    if (o.appends.length !== 1) { console.error("expected one append entry: " + JSON.stringify(o.appends)); process.exit(1); }
    if ((o.pending_appends || []).length !== 0) { console.error("non-strict must not name a pending_append: " + JSON.stringify(o.pending_appends)); process.exit(1); }
  ' "$TEST_DIR/pa-nonstrict.out" || log_fail "TEST-010: (a) non-strict output shape wrong"

  # (b) --strict --rev HEAD: the SAME append is now a named MISMATCH, exit 1.
  rc=0
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl --strict --rev HEAD --json > "$TEST_DIR/pa-strict.out" 2>&1 ) || rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-010: (b) --strict --rev HEAD must exit non-zero on an uncommitted append, got $rc: $(cat "$TEST_DIR/pa-strict.out")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (o.status !== "mismatch") { console.error("expected status mismatch, got " + o.status); process.exit(1); }
    if (o.mismatches.indexOf("docs/ai/EVENTS.jsonl") === -1) { console.error("the pending append must land in mismatches: " + JSON.stringify(o.mismatches)); process.exit(1); }
    if ((o.pending_appends || []).indexOf("docs/ai/EVENTS.jsonl") === -1) { console.error("pending_appends must name the path: " + JSON.stringify(o.pending_appends)); process.exit(1); }
  ' "$TEST_DIR/pa-strict.out" || log_fail "TEST-010: (b) strict output shape wrong"
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl --strict --rev HEAD > "$TEST_DIR/pa-strict-plain.out" 2>&1 ) || true
  grep -q 'pending append not committed' "$TEST_DIR/pa-strict-plain.out" \
    || log_fail "TEST-010: (b) plain-text output must name it 'pending append not committed': $(cat "$TEST_DIR/pa-strict-plain.out")"
  # It must NOT be mislabeled as a divergence — that name is reserved for a
  # rewritten middle line (TEST-008 (b)), a different cause.
  grep -q 'divergence' "$TEST_DIR/pa-strict-plain.out" \
    && log_fail "TEST-010: (b) a pending append is not a divergence — do not conflate the two labels: $(cat "$TEST_DIR/pa-strict-plain.out")"

  # (c) a real divergence (rewritten middle line) under --strict --rev HEAD
  # keeps its own "divergence" label — this fix must not blur the two.
  printf '{"n":1}\n{"n":2, "rewritten": true}\n' > "$d/docs/ai/EVENTS.jsonl"
  ( cd "$d" && node "$CHECK" docs/ai/EVENTS.jsonl --strict --rev HEAD > "$TEST_DIR/pa-diverge-plain.out" 2>&1 ) || true
  grep -q 'divergence — not an append' "$TEST_DIR/pa-diverge-plain.out" \
    || log_fail "TEST-010: (c) a real divergence under --strict must still say 'divergence — not an append': $(cat "$TEST_DIR/pa-diverge-plain.out")"

  log_pass "--strict --rev HEAD rejects an uncommitted HAZ-LEDGER append as a named 'pending append not committed' mismatch (exit non-zero); non-strict keeps it a clean advisory; a real divergence keeps its own label (TEST-010)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$CHECK" ] || log_fail "engine missing: $CHECK"
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_agents_rule
  test_002_release_names_unlogged_pr
  test_003_stale_add_shape
  test_004_clean_and_degrades
  test_005_skill_pr_wiring
  test_006_learned_triaged
  test_007_scope_ref_id_gate
  test_008_ledger_append_vs_divergence
  test_010_strict_rejects_pending_append
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
